import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall } from 'firebase-functions/v2/https';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import * as geofire from 'geofire-common';

export async function computeAndUpsertDemandHotspots(): Promise<{ updatedCells: number; prunedCells: number }> {
  const now = Date.now();
  const windowMs = 45 * 60 * 1000; // 45-minute moving window
  const sinceDate = new Date(now - windowMs);
  const expiryDate = new Date(now + 10 * 60 * 1000); // 10-minute validity

  // 1. Fetch recent rides
  let ridesSnap;
  try {
    ridesSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
      .where('createdAt', '>=', Timestamp.fromDate(sinceDate))
      .limit(300)
      .get();
  } catch (err) {
    console.warn('[DemandHeatmap] Firestore timestamp query fallback:', err);
    ridesSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
      .limit(100)
      .get();
  }

  // 2. Fetch online drivers to compute supply density
  const driversSnap = await db
    .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
    .where('isOnline', '==', true)
    .limit(500)
    .get();

  const driverCountsByGeohash6: Record<string, number> = {};
  for (const dDoc of driversSnap.docs) {
    const dData = dDoc.data();
    const gh = dData.currentLocation?.geohash;
    if (typeof gh === 'string' && gh.length >= 6) {
      const g6 = gh.slice(0, 6);
      driverCountsByGeohash6[g6] = (driverCountsByGeohash6[g6] || 0) + 1;
    }
  }

  // 3. Cluster ride requests into geohash6 cells
  interface CellCluster {
    count: number;
    openRequests: number;
    sumLat: number;
    sumLng: number;
  }

  const clusters: Record<string, CellCluster> = {};

  for (const rDoc of ridesSnap.docs) {
    const rData = rDoc.data();
    const pGeo = rData.pickup?.geopoint;
    if (!pGeo) continue;

    const lat = pGeo.latitude;
    const lng = pGeo.longitude;
    const g6 = geofire.geohashForLocation([lat, lng], 6);

    if (!clusters[g6]) {
      clusters[g6] = { count: 0, openRequests: 0, sumLat: 0, sumLng: 0 };
    }

    clusters[g6].count += 1;
    if (rData.status === 'REQUESTED' || rData.status === 'SEARCHING') {
      clusters[g6].openRequests += 1;
    }
    clusters[g6].sumLat += lat;
    clusters[g6].sumLng += lng;
  }

  // 4. Batch upsert demand hotspot cells
  const batch = db.batch();
  let updatedCount = 0;

  for (const [cellId, cluster] of Object.entries(clusters)) {
    const centerLat = cluster.sumLat / cluster.count;
    const centerLng = cluster.sumLng / cluster.count;
    const driversInCell = driverCountsByGeohash6[cellId] || 0;

    // Demand score calculation: ratio of open & recent requests to active driver supply
    const rawRatio = (cluster.openRequests * 1.5 + cluster.count * 0.5) / Math.max(1, driversInCell);
    const demandScore = Math.min(1.0, Math.round(rawRatio * 100) / 100);

    // Dynamic surge multiplier suggestion: 1.0x to 2.5x
    let surgeMultiplier = 1.0;
    if (demandScore >= 0.70) {
      surgeMultiplier = Math.min(2.5, Math.round((1.0 + (demandScore - 0.4) * 2.0) * 10) / 10);
    } else if (demandScore >= 0.40) {
      surgeMultiplier = Math.min(1.5, Math.round((1.0 + (demandScore - 0.3) * 1.2) * 10) / 10);
    }

    // Only persist cells with meaningful demand activity (>= 0.35)
    if (demandScore >= 0.35 || cluster.openRequests > 0) {
      const cellRef = db.collection(APP_CONSTANTS.COLLECTIONS.DEMAND_HOTSPOTS).doc(cellId);
      batch.set(
        cellRef,
        {
          cellId,
          lat: centerLat,
          lng: centerLng,
          demandScore,
          surgeMultiplier,
          requestCount: cluster.count,
          driverCount: driversInCell,
          radiusM: 650.0,
          updatedAt: FieldValue.serverTimestamp(),
          expiresAt: Timestamp.fromDate(expiryDate),
        },
        { merge: true }
      );
      updatedCount++;
    }
  }

  // 5. Prune expired hotspots
  let prunedCount = 0;
  try {
    const expiredSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.DEMAND_HOTSPOTS)
      .where('expiresAt', '<=', Timestamp.fromDate(new Date(now)))
      .limit(100)
      .get();

    for (const expDoc of expiredSnap.docs) {
      batch.delete(expDoc.ref);
      prunedCount++;
    }
  } catch (err) {
    console.warn('[DemandHeatmap] Expired prune query note:', err);
  }

  await batch.commit();
  console.log(`[DemandHeatmap] Updated ${updatedCount} hotspots, pruned ${prunedCount} expired cells.`);
  return { updatedCells: updatedCount, prunedCells: prunedCount };
}

// Scheduled trigger running every 5 minutes
export const updateDemandHotspots = onSchedule(
  {
    schedule: 'every 5 minutes',
    region: APP_CONSTANTS.REGION,
  },
  async () => {
    await computeAndUpsertDemandHotspots();
  }
);

// Callable function for on-demand driver cockpit refresh
export const refreshDemandHotspots = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async () => {
    return await computeAndUpsertDemandHotspots();
  }
);
