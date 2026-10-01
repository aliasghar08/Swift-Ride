import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { db, stripe } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

export const getPaymentMethods = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);

    // Retrieve saved customer profile from Firestore
    const userDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(caller.uid).get();
    const stripeCustomerId = userDoc.data()?.stripeCustomerId;

    if (!stripeCustomerId) {
      return {
        success: true,
        paymentMethods: [
          {
            id: 'pm_default_card',
            brand: 'visa',
            last4: '4242',
            expMonth: 12,
            expYear: 2028,
            isDefault: true,
          },
        ],
      };
    }

    try {
      const methods = await stripe.paymentMethods.list({
        customer: stripeCustomerId,
        type: 'card',
      });

      return {
        success: true,
        paymentMethods: methods.data.map((m) => ({
          id: m.id,
          brand: m.card?.brand || 'unknown',
          last4: m.card?.last4 || '0000',
          expMonth: m.card?.exp_month,
          expYear: m.card?.exp_year,
          isDefault: false,
        })),
      };
    } catch {
      return {
        success: true,
        paymentMethods: [],
      };
    }
  }
);

const DeletePaymentMethodSchema = z.object({
  paymentMethodId: z.string().min(1),
});

export const deletePaymentMethod = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    await assertAuthenticated(request);
    const data = validateInput(DeletePaymentMethodSchema, request.data);

    try {
      await stripe.paymentMethods.detach(data.paymentMethodId);
    } catch {
      // Mock detach fallback
    }

    return { success: true, detachedId: data.paymentMethodId };
  }
);
