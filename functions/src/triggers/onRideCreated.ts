import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { db } from '../config/firebase';
import { APP_CONSTANTS, REQUIRE_DRIVER_VERIFICATION } from '../config/constants';
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
      let q = db
        .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
        .where('isOnline', '==', true);

      if (REQUIRE_DRIVER_VERIFICATION) {
        q = q.where('isVerified', '==', true);
      }

      q = q
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

          // 3. Vehicle compatibility matching:
          const reqType = (rideData.vehicleType || '').toLowerCase();
          const dVehicleType = (dData.vehicleType || dData.vehicle?.type || '').toLowerCase();

          const isRideSevenSeater =
            reqType === 'sevenseater' ||
            reqType === 'seven_seater' ||
            reqType === '7seater' ||
            reqType === 'van' ||
            reqType === 'mpv';
          const isDriverSevenSeater =
            dVehicleType === 'sevenseater' ||
            dVehicleType === 'seven_seater' ||
            dVehicleType === '7seater' ||
            dVehicleType === 'van' ||
            dVehicleType === 'mpv';

          if (isRideSevenSeater) {
            // Seven-seater rides must only be dispatched to 7-seater MPV drivers
            if (!isDriverSevenSeater) {
              continue;
            }
          } else if (
            reqType === 'car' ||
            reqType === 'car_economy' ||
            reqType === 'car_ac' ||
            reqType === 'comfort' ||
            reqType === 'sedan'
          ) {
            // Standard car rides can be served by car drivers, OR 7-seater drivers who accept standard car rides
            const isDriverCar =
              dVehicleType === 'car' ||
              dVehicleType === 'sedan' ||
              dVehicleType === 'car_economy' ||
              dVehicleType === 'car_ac' ||
              dVehicleType === 'comfort';

            if (!isDriverCar) {
              if (isDriverSevenSeater) {
                if (dData.acceptsStandardCarRides === false) {
                  continue;
                }
              } else if (dVehicleType) {
                continue;
              }
            }
          } else if (reqType && dVehicleType) {
            if (reqType.includes('bike') && !dVehicleType.includes('bike')) continue;
            if (reqType.includes('rik') && !dVehicleType.includes('rik')) continue;
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
      rikshaw: 3,
      car: 4,
      sedan: 4,
      car_economy: 4,
      car_ac: 4,
      comfort: 4,
      sevenseater: 6,
      seven_seater: 6,
      '7seater': 6,
      van: 6,
      mpv: 6,
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
