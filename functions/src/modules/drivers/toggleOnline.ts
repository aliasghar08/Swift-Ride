import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS, REQUIRE_DRIVER_VERIFICATION } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const ToggleOnlineSchema = z.object({
  isOnline: z.boolean(),
  femalePassengersOnly: z.boolean().optional(),
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
          'Please enter your vehicle details before going online.'
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
    const plate = (driverData?.vehiclePlate || '').trim().toUpperCase();
    const make = (driverData?.vehicleMake || '').trim();
    const model = (driverData?.vehicleModel || '').trim();
    const year = Number(driverData?.vehicleYear);

    const dummyPlates = ['SWIFT-101', 'ABC-1234', 'AAA-0000', 'XXX-1234', 'ABC-1111', '000-0000', 'TEST-123'];
    const pakPlatePattern = /^[A-Z]{2,4}-[0-9]{1,4}(-[A-Z0-9]{1,4})?$/;
    const currentMaxYear = new Date().getFullYear() + 1;

    const hasValidVehicle = Boolean(
      plate &&
      !dummyPlates.includes(plate) &&
      pakPlatePattern.test(plate) &&
      make.length >= 2 &&
      model.length >= 2 &&
      !isNaN(year) &&
      year >= 1995 &&
      year <= currentMaxYear
    );

    if (data.isOnline && !hasValidVehicle) {
      throw new HttpsError(
        'failed-precondition',
        'Please enter valid Pakistani vehicle details (make, model, registered plate, year) before going online.'
      );
    }

    if (REQUIRE_DRIVER_VERIFICATION && data.isOnline && !isVerified) {
      throw new HttpsError(
        'failed-precondition',
        'Please complete document verification before going online.'
      );
    }

    if (data.femalePassengersOnly === true) {
      const isFemale = driverData?.gender?.toLowerCase() === 'female';
      if (!isFemale || !isVerified) {
        throw new HttpsError(
          'permission-denied',
          'Women Passengers Only mode is exclusively available for verified female drivers.'
        );
      }
    }

    await driverRef.update({
      isOnline: data.isOnline,
      ...(data.femalePassengersOnly !== undefined ? { femalePassengersOnly: data.femalePassengersOnly } : {}),
      ...(data.currentLocation
        ? {
            currentLocation: {
              ...data.currentLocation,
              lastSeenAt: FieldValue.serverTimestamp(),
            },
          }
        : {}),
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
