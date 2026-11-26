import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS, calculateSuggestedFare } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput, GeoLocationSchema } from '../../middleware/validation';
import { z } from 'zod';

const RequestRideSchema = z.object({
  pickup: GeoLocationSchema,
  dropoff: GeoLocationSchema,
  offeredFare: z.number().finite().min(50),
  distanceKm: z.number().finite().nonnegative(),
  durationMin: z.number().finite().nonnegative(),
  vehicleType: z.string().optional().default('car'),
  bookedSeats: z.number().int().min(1).max(6).optional().default(1),
  isAutoNegotiateEnabled: z.boolean().optional().default(false),
  maxAutoAcceptFare: z.number().finite().min(50).nullable().optional(),
  femaleDriverOnly: z.boolean().optional().default(false),
  riderGender: z.string().optional(),
});

export const requestRide = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(RequestRideSchema, request.data);

    // Enforce vehicle seat capacity bounds
    const vType = (data.vehicleType || 'car').toLowerCase();
    const maxCapacity = (vType === 'bike' || vType === 'moto') ? 1 : ((vType === 'rickshaw' || vType === 'auto') ? 3 : 4);
    const bookedSeats = data.bookedSeats ?? 1;
    if (bookedSeats > maxCapacity) {
      throw new HttpsError(
        'invalid-argument',
        `Booked seats (${bookedSeats}) exceeds maximum capacity of ${maxCapacity} for ${vType}.`
      );
    }

    // Fetch user profile to verify gender if femaleDriverOnly is requested
    const userDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(caller.uid).get();
    const userProfileGender = userDoc.data()?.gender?.toLowerCase();

    if (data.femaleDriverOnly) {
      if (userProfileGender && userProfileGender !== 'female') {
        throw new HttpsError(
          'failed-precondition',
          'Women-Only ride matching is exclusively for female passengers.'
        );
      }
      // If gender was specified in the request or user profile, save it
      if (!userProfileGender && data.riderGender?.toLowerCase() === 'female') {
        await userDoc.ref.set(
          {
            gender: 'female',
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    }

    const effectiveRiderGender = data.riderGender || userProfileGender || (data.femaleDriverOnly ? 'female' : null);

    // Generate 4-digit verification PIN for driver verification
    const pin = Math.floor(1000 + Math.random() * 9000).toString();
    const suggestedFare = calculateSuggestedFare(data.distanceKm, data.durationMin);

    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc();
    const ridePayload = {
      riderId: caller.uid,
      driverId: null,
      status: 'REQUESTED',
      pickup: data.pickup,
      dropoff: data.dropoff,
      offeredFare: data.offeredFare,
      suggestedFare,
      acceptedFare: null,
      distanceKm: data.distanceKm,
      durationMin: data.durationMin,
      vehicleType: data.vehicleType,
      bookedSeats: data.bookedSeats,
      isAutoNegotiateEnabled: data.isAutoNegotiateEnabled,
      maxAutoAcceptFare: data.maxAutoAcceptFare ?? null,
      femaleDriverOnly: data.femaleDriverOnly,
      riderGender: effectiveRiderGender,
      commissionAmount: Math.round(data.offeredFare * APP_CONSTANTS.COMMISSION_RATE_YEAR_ONE * 10) / 10, // 2% commission
      paymentIntentId: null,
      paymentStatus: 'pending',
      safetyFlags: [],
      shareToken: null,
      pin,
      createdAt: FieldValue.serverTimestamp(),
      completedAt: null,
    };

    await rideRef.set(ridePayload);

    return {
      success: true,
      rideId: rideRef.id,
      pin,
      suggestedFare,
      offeredFare: data.offeredFare,
    };
  }
);
