import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const SubscribePlanSchema = z.object({
  plan: z.enum(['DAILY', 'MONTHLY', 'YEARLY']),
});

export const subscribePlan = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertRole(request, ['driver', 'admin']);
    const { plan } = validateInput(SubscribePlanSchema, request.data);

    let durationDays = 1;
    let price = APP_CONSTANTS.SUBSCRIPTION_DAILY;

    if (plan === 'MONTHLY') {
      durationDays = 30;
      price = APP_CONSTANTS.SUBSCRIPTION_MONTHLY;
    } else if (plan === 'YEARLY') {
      durationDays = 365;
      price = APP_CONSTANTS.SUBSCRIPTION_YEARLY;
    }

    const expiresAt = new Date(Date.now() + durationDays * 24 * 60 * 60 * 1000);

    const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(caller.uid);
    await driverRef.update({
      subscriptionStatus: 'ACTIVE',
      subscriptionPlan: plan,
      subscriptionExpiresAt: Timestamp.fromDate(expiresAt),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      plan,
      price,
      status: 'ACTIVE',
      expiresAt: expiresAt.toISOString(),
    };
  }
);
