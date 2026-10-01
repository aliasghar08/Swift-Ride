import { onSchedule } from 'firebase-functions/v2/scheduler';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db, rtdb } from '../config/firebase';
import { APP_CONSTANTS } from '../config/constants';

export const generateWeeklyReports = onSchedule(
  {
    schedule: 'every monday 08:00',
    region: APP_CONSTANTS.REGION,
  },
  async () => {
    console.log('Generating SwiftRide weekly platform summary & driver performance digests.');
    const now = Date.now();
    const oneWeekAgo = new Date(now - 7 * 24 * 60 * 60 * 1000);

    const ridesSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
      .where('createdAt', '>=', Timestamp.fromDate(oneWeekAgo))
      .get();

    let totalFares = 0;
    let completedCount = 0;

    ridesSnap.docs.forEach((d) => {
      const data = d.data();
      if (data.status === 'COMPLETED') {
        completedCount++;
        totalFares += data.acceptedFare || data.offeredFare || 0;
      }
    });

    const reportRef = db.collection('weekly_reports').doc();
    await reportRef.set({
      periodStart: Timestamp.fromDate(oneWeekAgo),
      periodEnd: Timestamp.fromMillis(now),
      totalRidesRequested: ridesSnap.size,
      totalRidesCompleted: completedCount,
      grossBookingVolume: totalFares,
      totalCommissionSavedByDrivers: Math.round(totalFares * 0.13 * 100) / 100,
      createdAt: FieldValue.serverTimestamp(),
    });

    console.log(`Weekly report created with ID: ${reportRef.id}`);
  }
);

export const cleanupStaleRides = onSchedule(
  {
    schedule: 'every 15 minutes',
    region: APP_CONSTANTS.REGION,
  },
  async () => {
    // 10 minutes timeout for unanswered ride requests
    const staleThreshold = new Date(Date.now() - 10 * 60 * 1000);

    const staleRidesSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
      .where('status', '==', 'REQUESTED')
      .where('createdAt', '<=', Timestamp.fromDate(staleThreshold))
      .get();

    const batch = db.batch();
    staleRidesSnap.docs.forEach((doc) => {
      batch.update(doc.ref, {
        status: 'CANCELLED',
        cancellationReason: 'TIMEOUT_NO_DRIVER_ACCEPTED',
        cancelledAt: FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    console.log(`Cleaned up ${staleRidesSnap.size} stale ride requests.`);
  }
);

export const persistLocations = onSchedule(
  {
    schedule: 'every 1 minutes',
    region: APP_CONSTANTS.REGION,
  },
  async () => {
    try {
      const snapshot = await rtdb.ref(APP_CONSTANTS.RTDB_NODES.DRIVER_LOCATIONS).get();
      if (!snapshot.exists()) return;

      const locations = snapshot.val();
      const batch = db.batch();
      let writeCount = 0;

      for (const driverId in locations) {
        const loc = locations[driverId];
        if (loc.isOnline && loc.lat && loc.lng) {
          const auditRef = db
            .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
            .doc(driverId)
            .collection('location_history')
            .doc();

          batch.set(auditRef, {
            lat: loc.lat,
            lng: loc.lng,
            heading: loc.heading || 0,
            speed: loc.speed || 0,
            timestamp: FieldValue.serverTimestamp(),
          });
          writeCount++;
          if (writeCount >= 400) break; // Keep within Firestore 500-op batch limit
        }
      }

      if (writeCount > 0) {
        await batch.commit();
        console.log(`Audited ${writeCount} driver positions to Firestore.`);
      }
    } catch (err) {
      console.warn('Failed to persist RTDB locations:', err);
    }
  }
);
