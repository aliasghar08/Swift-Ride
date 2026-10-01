import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const ToggleOnlineSchema = z.object({
  isOnline: z.boolean(),
  currentLocation: z
    .object({
      lat: z.number().min(-90).max(90),
      lng: z.number().min(-180).max(180),
      geohash: z.string().min(1).max(12),
    })
    .optional(),
});

export const toggleOnline = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertRole(request, ['driver', 'admin']);
    const data = validateInput(ToggleOnlineSchema, request.data);

    const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(caller.uid);
    const driverDoc = await driverRef.get();

    if (!driverDoc.exists) {
      throw new HttpsError('not-found', 'Driver profile not found. Please complete driver onboarding.');
    }

    const driverData = driverDoc.data()!;
    if (data.isOnline && driverData.isVerified === false) {
      throw new HttpsError('failed-precondition', 'Cannot go online until driver documents are verified by admin.');
    }

    await driverRef.update({
      isOnline: data.isOnline,
      ...(data.currentLocation ? { currentLocation: data.currentLocation } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Also update RTDB
    if (data.isOnline && data.currentLocation) {
      await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.DRIVER_LOCATIONS}/${caller.uid}`).set({
        lat: data.currentLocation.lat,
        lng: data.currentLocation.lng,
        heading: 0,
        speed: 0,
        isOnline: true,
        timestamp: Date.now(),
      });
    } else {
      await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.DRIVER_LOCATIONS}/${caller.uid}/isOnline`).set(false);
    }

    return {
      success: true,
      driverId: caller.uid,
      isOnline: data.isOnline,
    };
  }
);
