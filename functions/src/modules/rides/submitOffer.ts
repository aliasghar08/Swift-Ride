import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const SubmitOfferSchema = z.object({
  rideId: z.string().min(1),
  counterFare: z.number().positive(),
  etaMinutes: z.number().nonnegative().optional(),
});

export const submitOffer = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const driver = await assertRole(request, ['driver', 'admin']);
    const data = validateInput(SubmitOfferSchema, request.data);

    // Verify ride exists and is still in REQUESTED status
    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId);
    const rideDoc = await rideRef.get();

    if (!rideDoc.exists) {
      throw new HttpsError('not-found', 'Ride not found.');
    }

    const rideData = rideDoc.data();
    if (rideData?.status !== 'REQUESTED') {
      throw new HttpsError('failed-precondition', 'Ride is no longer open for offers.');
    }

    // Check if driver profile exists, is verified, and active
    const driverDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(driver.uid).get();
    if (!driverDoc.exists) {
      throw new HttpsError('failed-precondition', 'Please complete your driver onboarding profile first.');
    }

    const driverData = driverDoc.data();
    if (driverData?.isVerified !== true) {
      throw new HttpsError('permission-denied', 'Driver profile is pending document verification.');
    }

    if (driverData?.status === 'banned' || driverData?.isSuspended === true) {
      throw new HttpsError('permission-denied', 'Your driver account is suspended.');
    }

    const plate = driverData?.vehiclePlate;
    if (!plate || plate === 'SWIFT-101' || plate === 'ABC-1234' || !driverData?.vehicleMake) {
      throw new HttpsError('failed-precondition', 'Please configure your vehicle details before submitting offers.');
    }

    const offerRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDE_OFFERS).doc();
    await offerRef.set({
      rideId: data.rideId,
      driverId: driver.uid,
      counterFare: data.counterFare,
      etaMinutes: data.etaMinutes || 5,
      driverRating: driverData?.rating || 5.0,
      vehicleInfo: {
        make: driverData.vehicleMake,
        model: driverData.vehicleModel || 'Vehicle',
        plate: driverData.vehiclePlate,
        color: driverData.vehicleColor || 'Standard',
      },
      status: 'PENDING',
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      offerId: offerRef.id,
      counterFare: data.counterFare,
    };
  }
);
