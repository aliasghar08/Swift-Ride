import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS, REQUIRE_DRIVER_VERIFICATION } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { sendPushToUser } from '../notifications';
import { z } from 'zod';

const SubmitOfferSchema = z.object({
  rideId: z.string().min(1),
  counterFare: z.number().finite().min(50),
  etaMinutes: z.number().finite().nonnegative().optional(),
});

export const submitOffer = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const driver = await assertRole(request, ['driver', 'admin']);
    const data = validateInput(SubmitOfferSchema, request.data);

    // Prevent duplicate pending offers from the same driver on the same ride
    const existingOfferQuery = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDE_OFFERS)
      .where('rideId', '==', data.rideId)
      .where('driverId', '==', driver.uid)
      .where('status', '==', 'PENDING')
      .limit(1)
      .get();

    if (!existingOfferQuery.empty) {
      throw new HttpsError('already-exists', 'You already have an active pending offer for this ride.');
    }

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
    if (!driverData) {
      throw new HttpsError('failed-precondition', 'Driver profile data is missing.');
    }

    if (REQUIRE_DRIVER_VERIFICATION && driverData.isVerified !== true) {
      throw new HttpsError('permission-denied', 'Driver profile is pending document verification.');
    }

    if (driverData.status === 'banned' || driverData.isSuspended === true) {
      throw new HttpsError('permission-denied', 'Your driver account is suspended.');
    }

    const plate = driverData.vehiclePlate;
    if (!plate || plate === 'SWIFT-101' || plate === 'ABC-1234' || !driverData.vehicleMake) {
      throw new HttpsError('failed-precondition', 'Please configure your vehicle details before submitting offers.');
    }

    // Women-Only mode offer submission gates
    if (rideData.femaleDriverOnly === true) {
      const isFemaleDriver = driverData.gender?.toLowerCase() === 'female' && driverData.isVerified === true;
      if (!isFemaleDriver) {
        throw new HttpsError(
          'permission-denied',
          'Women-Only rides are exclusively served by verified female captains.'
        );
      }
    }

    if (driverData.femalePassengersOnly === true) {
      if (rideData.riderGender?.toLowerCase() !== 'female') {
        throw new HttpsError(
          'failed-precondition',
          'You have Women Passengers Only mode enabled and cannot bid on this ride.'
        );
      }
    }

    const offerRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDE_OFFERS).doc();
    await offerRef.set({
      rideId: data.rideId,
      driverId: driver.uid,
      counterFare: data.counterFare,
      etaMinutes: data.etaMinutes || 5,
      driverRating: driverData.rating || 5.0,
      driverVerified: Boolean(driverData.isVerified),
      vehicleInfo: {
        make: driverData.vehicleMake || 'SwiftRide',
        model: driverData.vehicleModel || 'Vehicle',
        plate: driverData.vehiclePlate || 'SWIFT-101',
        color: driverData.vehicleColor || 'Standard',
      },
      status: 'PENDING',
      createdAt: FieldValue.serverTimestamp(),
    });

    // Notify rider of incoming driver offer/counter-offer
    if (rideData.riderId) {
      await sendPushToUser(rideData.riderId, {
        title: 'New Offer Received!',
        body: `${driverData.vehicleMake ? driverData.vehicleMake + ' Captain' : 'A driver'} offered Rs ${data.counterFare.toFixed(0)} for your ride.`,
        type: 'COUNTER_OFFER',
        rideId: data.rideId,
        extraData: {
          offerId: offerRef.id,
          counterFare: data.counterFare.toString(),
        },
      });
    }

    return {
      success: true,
      offerId: offerRef.id,
      counterFare: data.counterFare,
    };
  }
);
