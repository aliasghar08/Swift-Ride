import { onCall } from 'firebase-functions/v2/https';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';

export const getEarnings = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = assertHasToken(request);

    // Query completed rides for this driver
    const snapshot = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
      .where('driverId', '==', caller.uid)
      .where('status', '==', 'COMPLETED')
      .get();

    let totalEarnings = 0;
    let todayEarnings = 0;
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();

    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const fare = data.acceptedFare || data.offeredFare || 0;
      totalEarnings += fare;

      const completedAt = data.completedAt?.toDate?.() || new Date(data.createdAt?.toDate?.() || 0);
      if (completedAt.getTime() >= startOfToday) {
        todayEarnings += fare;
      }
    });

    // Subtract everything already committed to a payout. This previously
    // reported total earnings as "available", so a driver could request the same
    // balance over and over.
    const payoutsSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.PAYOUTS)
      .where('driverId', '==', caller.uid)
      .get();

    const committedStatuses = ['requested', 'processing', 'paid'];
    let committedPayouts = 0;
    let paidOut = 0;

    payoutsSnap.docs.forEach((doc) => {
      const data = doc.data();
      if (!committedStatuses.includes(data.status)) return;
      committedPayouts += data.amount || 0;
      if (data.status === 'paid') paidOut += data.amount || 0;
    });

    const commissionDeducted = Math.round(totalEarnings * 0.02 * 100) / 100;
    const netEarnings = Math.round((totalEarnings - commissionDeducted) * 100) / 100;
    const availablePayoutBalance =
      Math.round((netEarnings - committedPayouts) * 100) / 100;

    // Industry standard commission is ~13%, SwiftRide charges only 2% (saving drivers 11%)
    const standardCommissionSaved = Math.round(totalEarnings * (0.13 - 0.02) * 100) / 100;

    return {
      success: true,
      driverId: caller.uid,
      totalCompletedRides: snapshot.size,
      totalEarnings,
      todayEarnings,
      commissionDeducted, // 2% commission
      standardCommissionSaved,
      availablePayoutBalance,
      committedPayouts: Math.round(committedPayouts * 100) / 100,
      paidOut: Math.round(paidOut * 100) / 100,
      subscriptionStatus: 'ACTIVE', // Permanent 2% rate
    };
  }
);
