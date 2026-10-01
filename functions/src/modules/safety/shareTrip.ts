import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';
import * as crypto from 'crypto';

const ShareTripSchema = z.object({
  rideId: z.string().min(1),
});

export const shareTrip = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const { rideId } = validateInput(ShareTripSchema, request.data);

    const rideDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(rideId).get();
    if (!rideDoc.exists) {
      throw new HttpsError('not-found', 'Ride not found.');
    }

    const rideData = rideDoc.data()!;
    if (rideData.riderId !== caller.uid && caller.role !== 'admin') {
      throw new HttpsError('permission-denied', 'Only the rider can share their trip.');
    }

    // Generate random 16-byte hex token
    const shareToken = crypto.randomBytes(16).toString('hex');

    await db.collection(APP_CONSTANTS.COLLECTIONS.SHARED_TRIPS).doc(shareToken).set({
      rideId,
      riderId: caller.uid,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000), // Valid for 24h
    });

    await db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(rideId).update({
      shareToken,
    });

    return {
      success: true,
      shareToken,
      shareUrl: `https://swiftride.app/track?token=${shareToken}`,
    };
  }
);

const GetSharedTripSchema = z.object({
  shareToken: z.string().min(10),
});

export const getSharedTrip = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const { shareToken } = validateInput(GetSharedTripSchema, request.data);

    const shareDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.SHARED_TRIPS).doc(shareToken).get();
    if (!shareDoc.exists) {
      throw new HttpsError('not-found', 'Shared trip link is invalid or expired.');
    }

    const shareData = shareDoc.data()!;
    const rideDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(shareData.rideId).get();
    if (!rideDoc.exists) {
      throw new HttpsError('not-found', 'Ride no longer exists.');
    }

    const rideData = rideDoc.data()!;

    // Fetch driver details if assigned
    let driverInfo = null;
    if (rideData.driverId) {
      const driverDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(rideData.driverId).get();
      if (driverDoc.exists) {
        const dData = driverDoc.data()!;
        driverInfo = {
          vehicleMake: dData.vehicleMake,
          vehicleModel: dData.vehicleModel,
          vehiclePlate: dData.vehiclePlate,
          vehicleColor: dData.vehicleColor,
          rating: dData.rating,
        };
      }
    }

    // Fetch latest live location from RTDB
    let liveTracking = null;
    try {
      const snap = await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${shareData.rideId}`).get();
      if (snap.exists()) {
        liveTracking = snap.val();
      }
    } catch {
      // Non-critical fallback
    }

    return {
      success: true,
      status: rideData.status,
      pickup: rideData.pickup,
      dropoff: rideData.dropoff,
      driverInfo,
      liveTracking,
      updatedAt: Date.now(),
    };
  }
);
