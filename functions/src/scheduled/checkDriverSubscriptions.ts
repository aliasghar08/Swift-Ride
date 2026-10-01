import { onSchedule } from 'firebase-functions/v2/scheduler';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from '../config/firebase';
import { APP_CONSTANTS } from '../config/constants';

export const checkDriverSubscriptions = onSchedule(
  {
    schedule: 'every day 00:00',
    region: APP_CONSTANTS.REGION,
  },
  async () => {
    const now = Date.now();
    const gracePeriodMs = APP_CONSTANTS.SUBSCRIPTION_GRACE_DAYS * 24 * 60 * 60 * 1000;
    const thresholdDate = new Date(now - gracePeriodMs);

    const expiredDriversSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
      .where('subscriptionStatus', '==', 'ACTIVE')
      .where('subscriptionExpiresAt', '<=', Timestamp.fromDate(thresholdDate))
      .get();

    const batch = db.batch();
    expiredDriversSnap.docs.forEach((doc) => {
      batch.update(doc.ref, {
        subscriptionStatus: 'INACTIVE',
        isOnline: false, // Take offline if subscription expired
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    console.log(`Deactivated ${expiredDriversSnap.size} drivers with expired subscriptions.`);
  }
);
