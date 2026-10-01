import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';

export const getDashboardStats = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    await assertRole(request, ['admin']);

    const [ridesSnap, driversSnap, safetySnap, pendingDriversSnap] = await Promise.all([
      db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).get(),
      db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).where('isOnline', '==', true).get(),
      db.collection(APP_CONSTANTS.COLLECTIONS.SAFETY_EVENTS).where('resolvedAt', '==', null).get(),
      db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).where('isVerified', '==', false).get(),
    ]);

    let totalRides = ridesSnap.size;
    let completedRides = 0;
    let grossBookingVolume = 0;

    ridesSnap.docs.forEach((doc) => {
      const data = doc.data();
      if (data.status === 'COMPLETED') {
        completedRides++;
        grossBookingVolume += data.acceptedFare || data.offeredFare || 0;
      }
    });

    // Zero-commission year 1 savings calculation
    const zeroCommissionDriverSavings = Math.round(grossBookingVolume * 0.13 * 100) / 100;

    return {
      success: true,
      totalRides,
      completedRides,
      activeOnlineDrivers: driversSnap.size,
      pendingDriverVerifications: pendingDriversSnap.size,
      unresolvedSafetyEvents: safetySnap.size,
      grossBookingVolume: Math.round(grossBookingVolume * 100) / 100,
      zeroCommissionDriverSavings,
      commissionRate: 0.0, // Free first year
    };
  }
);
