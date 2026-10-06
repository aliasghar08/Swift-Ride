import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { db, stripe } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

/**
 * Settlement currency for the SwiftRide market.
 * Resolved server-side only — never accepted from the client.
 */
const CURRENCY = 'pkr';

const CreatePaymentIntentSchema = z.object({
  rideId: z.string().min(1),
  paymentMethodType: z.enum(['card', 'apple_pay', 'google_pay', 'cash']).default('card'),
});

export const createPaymentIntent = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(CreatePaymentIntentSchema, request.data);

    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId);
    const rideSnap = await rideRef.get();

    if (!rideSnap.exists) {
      throw new HttpsError('not-found', 'That trip no longer exists.');
    }

    const ride = rideSnap.data() as Record<string, unknown>;

    // Only the rider who owns the trip may pay for it.
    if (ride.riderId !== caller.uid) {
      throw new HttpsError('permission-denied', 'You are not the rider on this trip.');
    }

    if (ride.paymentStatus === 'paid') {
      throw new HttpsError('failed-precondition', 'This trip has already been paid for.');
    }

    // The payable amount is the fare the driver accepted, falling back to the
    // rider's offer. It is derived here and NEVER trusted from the client —
    // otherwise a caller could pay 1 unit for an expensive trip.
    const amount = Number(ride.acceptedFare ?? ride.offeredFare);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new HttpsError('failed-precondition', 'This trip has no payable fare yet.');
    }

    // Cash is settled in person; no Stripe intent is required.
    if (data.paymentMethodType === 'cash') {
      await rideRef.update({ paymentStatus: 'pending_cash', paymentMethod: 'cash' });
      return {
        clientSecret: null,
        paymentIntentId: null,
        status: 'pending_cash',
        amount,
      };
    }

    let paymentIntent;
    try {
      paymentIntent = await stripe.paymentIntents.create({
        amount: Math.round(amount * 100), // Stripe expects the smallest currency unit
        currency: CURRENCY,
        // Lets Stripe enable cards + Apple Pay + Google Pay + Link automatically,
        // which is what the client PaymentSheet expects.
        automatic_payment_methods: { enabled: true },
        metadata: {
          rideId: data.rideId,
          userId: caller.uid,
          platform: 'SwiftRide',
        },
      });
    } catch (err) {
      // Never fabricate a client secret on failure — the client would present a
      // payment sheet that can never succeed. Surface a real error instead.
      console.error('Stripe paymentIntents.create failed', {
        rideId: data.rideId,
        userId: caller.uid,
        err,
      });
      throw new HttpsError(
        'internal',
        'We could not start the payment. Nothing has been charged — please try again.'
      );
    }

    await rideRef.update({
      paymentIntentId: paymentIntent.id,
      paymentStatus: 'pending',
      paymentAmount: amount,
      paymentCurrency: CURRENCY,
    });

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
      status: paymentIntent.status,
      amount,
    };
  }
);
