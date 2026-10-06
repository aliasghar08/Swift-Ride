import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';
import { dispatchPayout, PAYOUT_SECRETS, type PayoutRail } from './payoutRails';

const RequestPayoutSchema = z.object({
  amount: z.number().positive(),
  rail: z.enum(['jazzcash', 'easypaisa', 'raast', 'manual']),
  /** Mobile wallet number (JazzCash/Easypaisa) or IBAN (Raast). */
  destination: z.string().min(4).max(64),
  /** Supplied by the client so a retry or double-tap cannot pay twice. */
  idempotencyKey: z.string().min(8).max(64),
});

/**
 * Payout states that reserve funds against the driver's balance.
 * A `failed` payout releases its funds back to the driver.
 */
const COMMITTED_STATUSES = ['requested', 'processing', 'paid'];

/** Sums a driver's completed-ride earnings. */
async function computeTotalEarnings(driverId: string): Promise<number> {
  const snapshot = await db
    .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
    .where('driverId', '==', driverId)
    .where('status', '==', 'COMPLETED')
    .get();

  return snapshot.docs.reduce((sum, doc) => {
    const data = doc.data();
    return sum + (data.acceptedFare || data.offeredFare || 0);
  }, 0);
}

/** Sums everything already committed to a payout for this driver. */
async function computeCommittedPayouts(driverId: string): Promise<number> {
  const snapshot = await db
    .collection(APP_CONSTANTS.COLLECTIONS.PAYOUTS)
    .where('driverId', '==', driverId)
    .get();

  return snapshot.docs
    .filter((doc) => COMMITTED_STATUSES.includes(doc.data().status))
    .reduce((sum, doc) => sum + (doc.data().amount || 0), 0);
}

export const requestPayout = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false, secrets: PAYOUT_SECRETS },
  async (request) => {
    const caller = await assertRole(request, ['driver', 'admin']);
    const data = validateInput(RequestPayoutSchema, request.data);

    const payoutsCol = db.collection(APP_CONSTANTS.COLLECTIONS.PAYOUTS);

    // 1. Idempotency — replaying a key returns the original payout rather than
    //    creating a second one.
    const existing = await payoutsCol
      .where('driverId', '==', caller.uid)
      .where('idempotencyKey', '==', data.idempotencyKey)
      .limit(1)
      .get();

    if (!existing.empty) {
      const doc = existing.docs[0];
      const record = doc.data();
      return {
        success: record.status === 'processing' || record.status === 'paid',
        payoutId: doc.id,
        status: record.status,
        amount: record.amount,
        rail: record.rail,
        message: record.failureReason ?? 'This payout has already been submitted.',
        replayed: true,
      };
    }

    // 2. Balance check. Previously `availablePayoutBalance` was simply total
    //    earnings, so a driver could be paid out repeatedly for the same trips.
    const [totalEarnings, committed] = await Promise.all([
      computeTotalEarnings(caller.uid),
      computeCommittedPayouts(caller.uid),
    ]);

    const available = Math.round((totalEarnings - committed) * 100) / 100;

    if (data.amount > available) {
      throw new HttpsError(
        'failed-precondition',
        available <= 0
          ? 'You have no balance available to withdraw right now.'
          : `You can withdraw up to ${available.toFixed(2)} PKR right now.`
      );
    }

    // 3. Record the request BEFORE dispatching, so a crash mid-flight leaves a
    //    visible record instead of losing the driver's money silently.
    const payoutRef = payoutsCol.doc();
    await payoutRef.set({
      driverId: caller.uid,
      amount: data.amount,
      currency: 'PKR',
      rail: data.rail,
      destination: data.destination,
      status: 'requested',
      idempotencyKey: data.idempotencyKey,
      totalEarnings,
      availableBefore: available,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // 4. Dispatch to the rail. An unconfigured rail fails closed — a payout is
    //    never reported as paid when no money moved.
    const result = await dispatchPayout(data.rail as PayoutRail, {
      payoutId: payoutRef.id,
      driverId: caller.uid,
      amount: data.amount,
      currency: 'PKR',
      destination: data.destination,
    });

    const status = result.accepted ? 'processing' : 'failed';

    await payoutRef.update({
      status,
      railReference: result.railReference ?? null,
      failureReason: result.accepted
        ? null
        : result.failureReason ?? 'The payout could not be started.',
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: result.accepted,
      payoutId: payoutRef.id,
      status,
      amount: data.amount,
      rail: data.rail,
      configurationMissing: result.configurationMissing ?? false,
      message: result.accepted
        ? 'Payout submitted. It will show as paid once the transfer settles.'
        : result.failureReason ??
          'The payout could not be started. Your balance is unchanged.',
    };
  }
);

const ConfirmPayoutSchema = z.object({
  payoutId: z.string().min(1),
  /** Set false when the transfer bounced or was cancelled. */
  settled: z.boolean(),
  railReference: z.string().max(120).optional(),
});

/**
 * Marks a submitted payout as actually settled, or returns the funds to the
 * driver. Admin-only, for rails settled out-of-band (`manual`).
 */
export const confirmPayout = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const admin = await assertRole(request, ['admin']);
    const data = validateInput(ConfirmPayoutSchema, request.data);

    const payoutRef = db.collection(APP_CONSTANTS.COLLECTIONS.PAYOUTS).doc(data.payoutId);
    const snap = await payoutRef.get();

    if (!snap.exists) {
      throw new HttpsError('not-found', 'That payout does not exist.');
    }

    const current = snap.data()?.status;
    if (current === 'paid' || current === 'failed') {
      throw new HttpsError('failed-precondition', 'That payout is already settled.');
    }

    await payoutRef.update({
      status: data.settled ? 'paid' : 'failed',
      railReference: data.railReference ?? snap.data()?.railReference ?? null,
      failureReason: data.settled ? null : 'Settlement failed; funds returned to your balance.',
      settledBy: admin.uid,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { success: true, payoutId: data.payoutId, status: data.settled ? 'paid' : 'failed' };
  }
);
