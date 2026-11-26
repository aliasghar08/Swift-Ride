import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { sendNotificationToUser } from '../notifications';
import { z } from 'zod';

const ApplyDriverPromoCodeSchema = z.object({
  code: z.string().min(3).max(20),
});

const DEFAULT_LAUNCH_PROMOS = new Set(['JHANG0', 'CAPTAIN0', 'SWIFT0', 'LAUNCH0']);

/**
 * Callable function: applyDriverPromoCode
 * Validates campaign promo codes or captain invite codes and unlocks 0% platform fee.
 */
export const applyDriverPromoCode = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const { code } = validateInput(ApplyDriverPromoCodeSchema, request.data);
    const cleanCode = code.trim().toUpperCase();

    const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(caller.uid);
    const driverSnap = await driverRef.get();

    if (!driverSnap.exists) {
      throw new HttpsError(
        'not-found',
        'Please complete your driver onboarding profile first.'
      );
    }

    const driverData = driverSnap.data()!;

    // Enforce one-time redemption per driver
    if (driverData.referredByCode) {
      throw new HttpsError(
        'failed-precondition',
        'You have already redeemed a launch promo or captain invite code.'
      );
    }

    let referredByDriverUid: string | null = null;
    let promoDescription = 'Launch Promotion';

    // 1. Check dynamic driver promo campaigns collection
    const campaignDoc = await db.collection('driver_promo_codes').doc(cleanCode).get();
    if (campaignDoc.exists && campaignDoc.data()?.isActive !== false) {
      promoDescription = campaignDoc.data()?.title || 'Launch Promotion';
    } else if (DEFAULT_LAUNCH_PROMOS.has(cleanCode)) {
      // 2. Built-in launch campaign codes
      promoDescription = `${cleanCode} Launch Promotion`;
    } else {
      // 3. Check if this is another captain's invite code (e.g. CAPT482)
      const captainQuery = await db
        .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
        .where('captainInviteCode', '==', cleanCode)
        .limit(1)
        .get();

      if (captainQuery.empty) {
        throw new HttpsError('not-found', 'Invalid promo code or Captain invite code.');
      }

      const referrerDoc = captainQuery.docs[0];
      if (referrerDoc.id === caller.uid) {
        throw new HttpsError('invalid-argument', 'You cannot use your own captain referral code.');
      }

      referredByDriverUid = referrerDoc.id;
      promoDescription = 'Captain Referral';
    }

    // Calculate 30-day fee waiver
    const nowMs = Date.now();
    const currentWaiverMs = driverData.feeWaiverUntil?.toDate
      ? driverData.feeWaiverUntil.toDate().getTime()
      : 0;
    const baseMs = Math.max(nowMs, currentWaiverMs);
    const newWaiverDate = new Date(baseMs + 30 * 24 * 60 * 60 * 1000); // +30 days

    await driverRef.update({
      referredByCode: cleanCode,
      referredByDriverUid,
      feeWaiverUntil: Timestamp.fromDate(newWaiverDate),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      code: cleanCode,
      description: promoDescription,
      message: '0% Platform Fee Unlocked for 30 Days!',
      feeWaiverUntil: newWaiverDate.toISOString(),
    };
  }
);

/**
 * Handles driver rewards and referral milestone progression on completed trips.
 */
export async function processDriverTripCompletionRewards(driverId: string): Promise<void> {
  const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(driverId);

  await db.runTransaction(async (transaction) => {
    const driverDoc = await transaction.get(driverRef);
    if (!driverDoc.exists) return;

    const driverData = driverDoc.data()!;
    const weeklyRides = (driverData.weeklyCompletedRides ?? 0) + 1;
    const updates: Record<string, any> = {
      weeklyCompletedRides: weeklyRides,
      updatedAt: FieldValue.serverTimestamp(),
    };

    // 1. Weekly Target: 15 rides -> +7 days 0% fee waiver
    if (weeklyRides === 15) {
      const nowMs = Date.now();
      const currentWaiverMs = driverData.feeWaiverUntil?.toDate
        ? driverData.feeWaiverUntil.toDate().getTime()
        : 0;
      const baseMs = Math.max(nowMs, currentWaiverMs);
      const extendedWaiver = new Date(baseMs + 7 * 24 * 60 * 60 * 1000);
      updates.feeWaiverUntil = Timestamp.fromDate(extendedWaiver);

      // Notify Driver of Weekly Target achievement
      sendNotificationToUser(driverId, {
        title: 'Target Achieved! 🎯',
        body: '15 rides completed this week! 0% Platform Fee unlocked for 7 days.',
        data: { type: 'FEE_WAIVER_UNLOCKED' },
      }).catch(() => {});
    }

    // 2. 5-Driver Referral Qualification Check:
    // When referred driver has completed 3 rides AND is verified (and haven't awarded before)
    const totalRides = (driverData.totalRides ?? 0) + 1;
    const isVerified = driverData.isVerified === true;
    const referrerUid = driverData.referredByDriverUid;
    const alreadyAwarded = driverData.referralMilestoneAwarded === true;

    if (referrerUid && isVerified && totalRides >= 3 && !alreadyAwarded) {
      updates.referralMilestoneAwarded = true;

      const referrerRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(referrerUid);
      const referrerDoc = await transaction.get(referrerRef);

      if (referrerDoc.exists) {
        const refData = referrerDoc.data()!;
        const currentReferrals = (refData.verifiedReferralsCount ?? 0) + 1;
        const nowMs = Date.now();
        const refWaiverMs = refData.feeWaiverUntil?.toDate
          ? refData.feeWaiverUntil.toDate().getTime()
          : 0;
        let baseRefMs = Math.max(nowMs, refWaiverMs);
        let daysToAdd = 7; // +7 days per verified active referral

        const badges: string[] = Array.isArray(refData.badges) ? [...refData.badges] : [];
        let unlockedBadge = false;

        // 5-Driver Milestone check: unlock FOUNDING_CAPTAIN and grant +30 days extra
        if (currentReferrals >= 5 && !badges.includes('FOUNDING_CAPTAIN')) {
          badges.push('FOUNDING_CAPTAIN');
          daysToAdd += 30; // +30 days bonus for Founding Fleet
          unlockedBadge = true;
        }

        const newRefWaiver = new Date(baseRefMs + daysToAdd * 24 * 60 * 60 * 1000);

        transaction.update(referrerRef, {
          verifiedReferralsCount: currentReferrals,
          badges,
          feeWaiverUntil: Timestamp.fromDate(newRefWaiver),
          updatedAt: FieldValue.serverTimestamp(),
        });

        // Notify Referrer
        if (unlockedBadge) {
          sendNotificationToUser(referrerUid, {
            title: 'Founding Captain Unlocked! 🎖️',
            body: 'Congratulations! 5 verified captains joined with your code. You unlocked the Founding Captain badge + 30 days of 0% fee!',
            data: { type: 'BADGE_UNLOCKED', badge: 'FOUNDING_CAPTAIN' },
          }).catch(() => {});
        } else {
          sendNotificationToUser(referrerUid, {
            title: 'Captain Referral Qualified! 🚗',
            body: `A captain you invited completed 3 rides with verified documents. You earned 7 days of 0% platform fee! (${currentReferrals}/5 joined)`,
            data: { type: 'REFERRAL_QUALIFIED' },
          }).catch(() => {});
        }
      }
    }

    transaction.update(driverRef, updates);
  });
}
