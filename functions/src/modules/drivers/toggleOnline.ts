import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';
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
    const caller = assertHasToken(request);
    const data = validateInput(ToggleOnlineSchema, request.data);

    // 1. Ensure user profile exists and has role 'driver'
    const userRef = db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(caller.uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      await userRef.set({
        phone: request.auth?.token?.phone_number || '',
        fullName: 'SwiftRide Driver',
        role: 'driver',
        rating: 5.0,
        totalRides: 0,
        fcmTokens: [],
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (userDoc.data()?.role !== 'driver' && userDoc.data()?.role !== 'admin') {
      await userRef.update({
        role: 'driver',
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // 2. Ensure driver profile exists, has registered vehicle details, and is verified
    const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(caller.uid);
    const driverDoc = await driverRef.get();

    if (!driverDoc.exists) {
      if (data.isOnline) {
        throw new HttpsError(
          'failed-precondition',
          'Please enter your vehicle details and complete document verification before going online.'
        );
      }
      return { success: false, isOnline: false };
    }

    const driverData = driverDoc.data();
    if (data.isOnline && (driverData?.status === 'banned' || driverData?.isSuspended === true)) {
      throw new HttpsError(
        'permission-denied',
        'Your driver account is suspended. Please contact support.'
      );
    }

    const isVerified = driverData?.isVerified === true;
    const plate = driverData?.vehiclePlate;
    const hasValidVehicle = Boolean(
      plate &&
      plate !== 'SWIFT-101' &&
      plate !== 'ABC-1234' &&
      driverData?.vehicleMake
    );

    if (data.isOnline && (!isVerified || !hasValidVehicle)) {
      throw new HttpsError(
        'failed-precondition',
        'Please enter complete vehicle details (legal & visual) and complete document verification before going online.'
      );
    }

    await driverRef.update({
      isOnline: data.isOnline,
      ...(data.currentLocation ? { currentLocation: data.currentLocation } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // 3. Update RTDB live driver locations
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
