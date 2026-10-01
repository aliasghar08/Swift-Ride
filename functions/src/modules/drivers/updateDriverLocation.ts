import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { rtdb } from '../../config/firebase';
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
      const rideTrackRef = rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${data.activeRideId}`);
      await rideTrackRef.update({
        driverId: caller.uid,
        lat: data.lat,
        lng: data.lng,
        heading: data.heading,
        speed: data.speed,
        timestamp,
      });
    }

    return { success: true, timestamp };
  }
);
