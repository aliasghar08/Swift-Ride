import { onRequest } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, stripe } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import Stripe from 'stripe';

export const stripeWebhook = onRequest(
  { region: APP_CONSTANTS.REGION, memory: '512MiB' },
  async (req, res) => {
    const sig = req.headers['stripe-signature'];
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || 'whsec_placeholder';

    let event: Stripe.Event;

    try {
      if (sig && webhookSecret && !webhookSecret.includes('placeholder')) {
        event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
      } else {
        event = req.body as Stripe.Event;
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Unknown webhook signature error';
      res.status(400).send(`Webhook Error: ${message}`);
      return;
    }

    try {
      switch (event.type) {
        case 'payment_intent.succeeded': {
          const paymentIntent = event.data.object as Stripe.PaymentIntent;
          const rideId = paymentIntent.metadata?.rideId;
          const userId = paymentIntent.metadata?.userId;

          if (rideId) {
            // Update ride payment status
            await db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(rideId).update({
              paymentStatus: 'paid',
              paymentIntentId: paymentIntent.id,
              paidAt: FieldValue.serverTimestamp(),
            });

            // Log payment record in payments collection
            await db.collection(APP_CONSTANTS.COLLECTIONS.PAYMENTS).doc(paymentIntent.id).set({
              rideId,
              userId: userId || 'unknown',
              amount: paymentIntent.amount / 100,
              method: 'CARD',
              stripePaymentIntentId: paymentIntent.id,
              status: 'succeeded',
              createdAt: FieldValue.serverTimestamp(),
            });
          }
          break;
        }

        case 'account.updated': {
          const account = event.data.object as Stripe.Account;
          // Update driver's Stripe Connect status
          const driversSnapshot = await db
            .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
            .where('stripeAccountId', '==', account.id)
            .limit(1)
            .get();

          if (!driversSnapshot.empty) {
            const driverRef = driversSnapshot.docs[0].ref;
            await driverRef.update({
              payoutStatus: account.payouts_enabled ? 'active' : 'pending',
              updatedAt: FieldValue.serverTimestamp(),
            });
          }
          break;
        }

        case 'transfer.created': {
          const transfer = event.data.object as Stripe.Transfer;
          console.log(`Transfer created for account: ${transfer.destination}, amount: ${transfer.amount}`);
          break;
        }
      }

      res.status(200).json({ received: true });
    } catch (err) {
      console.error('Error handling webhook event:', err);
      res.status(500).send('Internal Server Error');
    }
  }
);
