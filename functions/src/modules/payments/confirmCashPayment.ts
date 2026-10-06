import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

/**
 * Settlement currency for the SwiftRide market. Resolved server-side only.
 */
const CURRENCY = 'pkr';

const ConfirmCashPaymentSchema = z.object({
  rideId: z.string().min(1),
});

/**
 * Records that the driver received cash for a completed trip.
 *
 * Cash is the one rail that needs no external provider, but without this the
 * trip's `paymentStatus` stayed `pending_cash` forever: the rider's choice of
 * "Cash" was a local-only string and nothing ever marked the trip settled.
 *
 * The amount is derived from the ride document, never from the caller — a driver
 * must not be able to declare how much they were paid. This confirms receipt of
 * cash; it does not move money, and the record says so.
 */
export const confirmCashPayment = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertRole(request, ['driver', 'admin']);
    const data = validateInput(ConfirmCashPaymentSchema, request.data);

    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId);
    const rideSnap = await rideRef.get();

    if (!rideSnap.exists) {
      throw new HttpsError('not-found', 'That trip no longer exists.');
    }

    const ride = rideSnap.data() as Record<string, unknown>;

    // Only the driver who actually drove the trip may confirm receipt.
    const isAdmin = caller.role === 'admin';
    if (!isAdmin && ride.driverId !== caller.uid) {
      throw new HttpsError('permission-denied', 'You were not the driver on this trip.');
    }

    if (ride.status !== 'COMPLETED') {
      throw new HttpsError(
        'failed-precondition',
        'Cash can only be recorded once the trip is complete.'
      );
    }

    if (ride.paymentStatus === 'paid') {
      throw new HttpsError('failed-precondition', 'This trip is already marked as paid.');
    }

    // Guard against confirming cash on a trip the rider intends to pay another way.
    if (ride.paymentMethod && ride.paymentMethod !== 'cash') {
      throw new HttpsError(
        'failed-precondition',
        `This trip is set to be paid by ${ride.paymentMethod}, not cash.`
      );
    }

    const amount = Number(ride.acceptedFare ?? ride.offeredFare);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new HttpsError('failed-precondition', 'This trip has no payable fare.');
    }

    await rideRef.update({
      paymentStatus: 'paid',
      paymentMethod: 'cash',
      paymentAmount: amount,
      paymentCurrency: CURRENCY,
      paidAt: FieldValue.serverTimestamp(),
    });

    // Ledger entry. `settledBy` records that this was an in-person confirmation
    // rather than a provider settlement.
    await db.collection(APP_CONSTANTS.COLLECTIONS.PAYMENTS).add({
      rideId: data.rideId,
      userId: ride.riderId,
      driverId: ride.driverId ?? null,
      amount,
      currency: CURRENCY,
      method: 'cash',
      status: 'paid',
      settledBy: isAdmin ? 'admin' : 'driver',
      provider: null,
      providerReference: null,
      confirmedBy: caller.uid,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      amount,
      currency: CURRENCY,
      paymentStatus: 'paid',
    };
  }
);
