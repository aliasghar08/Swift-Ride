import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { db } from '../config/firebase';
import { APP_CONSTANTS } from '../config/constants';
import { notifyDriversOfRide, notifyDriverOfPoolDetour } from '../modules/notifications';
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
    const dropoffGeo = rideData.dropoff?.geopoint;
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

          // Women-Only mode dispatch rules:
          // 1. If passenger requested female captain only, require female verified driver
          if (rideData.femaleDriverOnly === true) {
            if (dData.gender?.toLowerCase() !== 'female' || dData.isVerified !== true) {
              continue;
            }
          }

          // 2. If driver configured Women Passengers Only, require female rider
          if (dData.femalePassengersOnly === true) {
            if (rideData.riderGender?.toLowerCase() !== 'female') {
              continue;
            }
          }

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
    const vehicleSeats: Record<string, number> = {
      bike: 1,
      rickshaw: 3,
      car_economy: 4,
      car_ac: 4,
      comfort: 4,
    };
    const totalSeats = vehicleSeats[rideData.vehicleType] ?? 4;
    const bookedSeats = rideData.bookedSeats ?? 1;

    await notifyDriversOfRide(
      topDriverIds,
      rideId,
      rideData.pickup.address,
      rideData.offeredFare,
      bookedSeats,
      totalSeats
    );

    console.log(
      `Dispatched ride request ${rideId} to ${topDriverIds.length} nearby drivers within ${APP_CONSTANTS.MATCHING_INITIAL_RADIUS_KM}km.`
    );

    // 5. En-Route Corridor Matching (Dynamic Seat Pooling)
    // If vehicle allows pooling (seats >= 2 and bookedSeats < totalSeats) and dropoff is present
    if (totalSeats >= 2 && dropoffGeo) {
      try {
        const activeRidesSnap = await db
          .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
          .where('status', 'in', ['ACCEPTED', 'DRIVER_ARRIVED', 'IN_PROGRESS'])
          .limit(20)
          .get();

        const dropoffCoord: [number, number] = [dropoffGeo.latitude, dropoffGeo.longitude];

        for (const aDoc of activeRidesSnap.docs) {
          const aRide = aDoc.data();
          if (!aRide.driverId || aDoc.id === rideId) continue;

          // Check remaining capacity on the active vehicle
          const activeBooked = aRide.bookedSeats ?? 1;
          const activeVehicleSeats = vehicleSeats[aRide.vehicleType] ?? 4;
          const activeRemaining = aRide.remainingSeats ?? Math.max(0, activeVehicleSeats - activeBooked);

          if (activeRemaining < bookedSeats) continue;

          // Driver location
          const dLat = aRide.driverLocation?.lat;
          const dLng = aRide.driverLocation?.lng;
          const driverCoord: [number, number] =
            dLat !== undefined && dLng !== undefined
              ? [dLat, dLng]
              : aRide.pickup?.geopoint
              ? [aRide.pickup.geopoint.latitude, aRide.pickup.geopoint.longitude]
              : center;

          const existingDropoffGeo = aRide.dropoff?.geopoint;
          if (!existingDropoffGeo) continue;
          const existingDropoffCoord: [number, number] = [
            existingDropoffGeo.latitude,
            existingDropoffGeo.longitude,
          ];

          // Haversine Detour Calculation:
          // Added Detour = dist(Driver, NewPickup) + dist(NewPickup, NewDropoff) + dist(NewDropoff, ExistingDropoff) - dist(Driver, ExistingDropoff)
          const distDriverToNewPickup = geofire.distanceBetween(driverCoord, center);
          const distNewPickupToNewDrop = geofire.distanceBetween(center, dropoffCoord);
          const distNewDropToExistingDrop = geofire.distanceBetween(dropoffCoord, existingDropoffCoord);
          const distDirect = geofire.distanceBetween(driverCoord, existingDropoffCoord);

          const addedDetourKm = Math.max(
            0,
            distDriverToNewPickup + distNewPickupToNewDrop + distNewDropToExistingDrop - distDirect
          );

          if (addedDetourKm <= APP_CONSTANTS.POOL_MAX_DETOUR_KM) {
            await notifyDriverOfPoolDetour(aRide.driverId, {
              rideId,
              parentRideId: aDoc.id,
              detourKm: addedDetourKm,
              extraEarningsPkr: rideData.offeredFare,
              pickupAddress: rideData.pickup.address,
              dropoffAddress: rideData.dropoff.address,
              bookedSeats,
            });
            console.log(
              `Dispatched en-route pool offer for ride ${rideId} to driver ${aRide.driverId} (detour: ${addedDetourKm.toFixed(2)} km)`
            );
          }
        }
      } catch (poolErr) {
        console.warn('En-route pool matching note:', poolErr);
      }
    }
  }
);
