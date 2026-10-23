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
  offeredFare: z.number().positive(),
  distanceKm: z.number().nonnegative(),
  durationMin: z.number().nonnegative(),
  vehicleType: z.string().optional().default('car'),
  bookedSeats: z.number().int().min(1).max(6).optional().default(1),
  isAutoNegotiateEnabled: z.boolean().optional().default(false),
  maxAutoAcceptFare: z.number().nullable().optional(),
});

export const requestRide = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(RequestRideSchema, request.data);

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
      commissionAmount: 0.0, // 0 commission in year 1
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
