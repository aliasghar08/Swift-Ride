import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { db } from '../config/firebase';
import { APP_CONSTANTS } from '../config/constants';
import { notifyDriversOfRide } from '../modules/notifications';
import * as geofire from 'geofire-common';

export const onRideCreated = onDocumentCreated(
  {
    document: `${APP_CONSTANTS.COLLECTIONS.RIDES}/{rideId}`,
    region: APP_CONSTANTS.REGION,
    memory: '512MiB',
    timeoutSeconds: 300,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const rideData = snapshot.data();
    const rideId = event.params.rideId;

    if (rideData.status !== 'REQUESTED') return;

    const pickupGeo = rideData.pickup?.geopoint;
    if (!pickupGeo) return;

    const center: [number, number] = [pickupGeo.latitude, pickupGeo.longitude];
    const radiusInM = APP_CONSTANTS.MATCHING_INITIAL_RADIUS_KM * 1000;

    // 1. Calculate geohash query bounds
    const bounds = geofire.geohashQueryBounds(center, radiusInM);
    const matchingDrivers: Array<{ id: string; distanceKm: number }> = [];

    // 2. Query online drivers within proximity bounds
    for (const b of bounds) {
      const q = db
        .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
        .where('isOnline', '==', true)
        .where('isVerified', '==', true)
        .orderBy('currentLocation.geohash')
        .startAt(b[0])
        .endAt(b[1]);

      try {
        const snap = await q.get();
        for (const doc of snap.docs) {
          const dData = doc.data();
          const lat = dData.currentLocation?.lat;
          const lng = dData.currentLocation?.lng;
          if (lat !== undefined && lng !== undefined) {
            const distanceInKm = geofire.distanceBetween([lat, lng], center);
            if (distanceInKm <= APP_CONSTANTS.MATCHING_INITIAL_RADIUS_KM) {
              matchingDrivers.push({ id: doc.id, distanceKm: distanceInKm });
            }
          }
        }
      } catch (err) {
        // Fallback for mock/local indexing
        console.warn('Geohash query note:', err);
      }
    }

    // 3. Sort drivers by distance and take top 20
    matchingDrivers.sort((a, b) => a.distanceKm - b.distanceKm);
    const topDriverIds = matchingDrivers
      .slice(0, APP_CONSTANTS.MAX_BROADCAST_DRIVERS)
      .map((d) => d.id);

    // 4. Send FCM notifications to matching drivers
    await notifyDriversOfRide(
      topDriverIds,
      rideId,
      rideData.pickup.address,
      rideData.offeredFare
    );

    console.log(
      `Dispatched ride request ${rideId} to ${topDriverIds.length} nearby drivers within ${APP_CONSTANTS.MATCHING_INITIAL_RADIUS_KM}km.`
    );
  }
);
