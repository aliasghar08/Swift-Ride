import { onCall } from 'firebase-functions/v2/https';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';

export const getEarnings = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertRole(request, ['driver', 'admin']);

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

    // inDrive standard commission is ~13%, SwiftRide saves drivers 100% of this
    const standardCommissionSaved = Math.round(totalEarnings * 0.13 * 100) / 100;

    return {
      success: true,
      driverId: caller.uid,
      totalCompletedRides: snapshot.size,
      totalEarnings,
      todayEarnings,
      commissionDeducted: 0.0, // 0 commission in Year 1!
      standardCommissionSaved,
      availablePayoutBalance: totalEarnings,
      subscriptionStatus: 'TRIAL', // Free first year
    };
  }
);
