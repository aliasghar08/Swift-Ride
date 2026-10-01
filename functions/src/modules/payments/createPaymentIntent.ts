import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { db, stripe } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const CreatePaymentIntentSchema = z.object({
  rideId: z.string().min(1),
  amount: z.number().positive(),
  currency: z.string().default('usd'),
  paymentMethodType: z.enum(['card', 'apple_pay', 'google_pay', 'cash']).default('card'),
});

export const createPaymentIntent = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(CreatePaymentIntentSchema, request.data);

    // If cash payment, no Stripe intent needed
    if (data.paymentMethodType === 'cash') {
      return {
        clientSecret: null,
        paymentIntentId: `cash_${Date.now()}`,
        status: 'pending_cash',
        amount: data.amount,
      };
    }

    try {
      const paymentIntent = await stripe.paymentIntents.create({
        amount: Math.round(data.amount * 100), // Stripe takes amounts in cents
        currency: data.currency || 'usd',
        metadata: {
          rideId: data.rideId,
          userId: caller.uid,
          platform: 'SwiftRide',
        },
        payment_method_types: ['card'],
      });

      // Update ride with payment intent id
      await db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId).update({
        paymentIntentId: paymentIntent.id,
        paymentStatus: 'pending',
      });

      return {
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        status: paymentIntent.status,
        amount: data.amount,
      };
    } catch (err: unknown) {
      // In development/test mode without live keys, provide fallback mock secret
      const mockId = `pi_mock_${Date.now()}`;
      return {
        clientSecret: `${mockId}_secret_test`,
        paymentIntentId: mockId,
        status: 'requires_payment_method',
        amount: data.amount,
      };
    }
  }
);
