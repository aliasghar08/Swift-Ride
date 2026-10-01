import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, stripe } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const RequestPayoutSchema = z.object({
  amount: z.number().positive(),
  method: z.enum(['INSTANT_CARD', 'BANK_TRANSFER']).default('INSTANT_CARD'),
});

export const requestPayout = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertRole(request, ['driver', 'admin']);
    const data = validateInput(RequestPayoutSchema, request.data);

    const driverDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(caller.uid).get();
    if (!driverDoc.exists) {
      throw new HttpsError('not-found', 'Driver profile not found.');
    }

    const driverData = driverDoc.data()!;
    const stripeAccountId = driverData.stripeAccountId;

    let payoutId = `payout_sim_${Date.now()}`;

    // If live Stripe Connect account is connected, execute real transfer
    if (stripeAccountId && !stripeAccountId.startsWith('mock_')) {
      try {
        const transfer = await stripe.transfers.create({
          amount: Math.round(data.amount * 100),
          currency: 'pkr',
          destination: stripeAccountId,
          description: `SwiftRide Driver Payout (${data.method})`,
        });
        payoutId = transfer.id;
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : 'Stripe transfer failed';
        throw new HttpsError('internal', `Payout transfer failed: ${message}`);
      }
    }

    // Record payout in driver ledger
    const payoutRecordRef = db
      .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
      .doc(caller.uid)
      .collection('payouts')
      .doc();

    await payoutRecordRef.set({
      amount: data.amount,
      method: data.method,
      payoutId,
      status: 'succeeded',
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      payoutId,
      amount: data.amount,
      method: data.method,
      status: 'succeeded',
    };
  }
);
