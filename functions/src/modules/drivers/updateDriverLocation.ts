import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const UpdateDriverLocationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  heading: z.number().default(0),
  speed: z.number().default(0),
  activeRideId: z.string().optional(),
});

export const updateDriverLocation = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertRole(request, ['driver', 'admin']);
    const data = validateInput(UpdateDriverLocationSchema, request.data);

    const timestamp = Date.now();

    // 1. Write to RTDB driver_locations node
    const driverLocRef = rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.DRIVER_LOCATIONS}/${caller.uid}`);
    await driverLocRef.set({
      lat: data.lat,
      lng: data.lng,
      heading: data.heading,
      speed: data.speed,
      timestamp,
      updatedAt: timestamp,
      isOnline: true,
    });

    // 2. If currently in an active ride, also update ride_tracking node
    if (data.activeRideId) {
      const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.activeRideId);
      const rideSnap = await rideRef.get();

      // Only the driver actually assigned to this trip may publish telemetry for
      // it. Without this check any driver could overwrite another trip's pin.
      if (!rideSnap.exists || rideSnap.data()?.driverId !== caller.uid) {
        throw new HttpsError(
          'permission-denied',
          'You are not the assigned driver on that trip.'
        );
      }

      const rideTrackRef = rtdb.ref(
        `${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${data.activeRideId}`
      );
      await rideTrackRef.update({
        driverId: caller.uid,
        lat: data.lat,
        lng: data.lng,
        heading: data.heading,
        speed: data.speed,
        timestamp,
      });

      // Mirror onto the ride document so the rider can render the real driver
      // position through the ride subscription it already holds, without a
      // second realtime-database dependency on the client.
      await rideRef.update({
        driverLocation: {
          lat: data.lat,
          lng: data.lng,
          heading: data.heading,
          speed: data.speed,
          updatedAt: timestamp,
        },
      });
    }

    return { success: true, timestamp };
  }
);
