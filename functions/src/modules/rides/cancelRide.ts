import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS, calculateCancellationFee } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const CancelRideSchema = z.object({
  rideId: z.string().min(1),
  reason: z.string().max(200).optional(),
});

export const cancelRide = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(CancelRideSchema, request.data);

    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId);
    const rideDoc = await rideRef.get();

    if (!rideDoc.exists) {
      throw new HttpsError('not-found', 'Ride not found.');
    }

    const rideData = rideDoc.data()!;
    const isRider = rideData.riderId === caller.uid;
    const isDriver = rideData.driverId === caller.uid;
    const isAdmin = caller.role === 'admin';

    if (!isRider && !isDriver && !isAdmin) {
      throw new HttpsError('permission-denied', 'Only participants or admin can cancel this ride.');
    }

    if (['COMPLETED', 'CANCELLED'].includes(rideData.status)) {
      throw new HttpsError('failed-precondition', `Cannot cancel a ride that is already ${rideData.status}.`);
    }

    const cancellationFee = isRider ? calculateCancellationFee(rideData.status) : 0;

    await rideRef.update({
      status: 'CANCELLED',
      cancelledBy: caller.uid,
      cancellationReason: data.reason || 'User cancelled',
      cancellationFee,
      driverPenalized: isDriver,
      cancelledAt: FieldValue.serverTimestamp(),
    });

    // Update RTDB tracking
    await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${data.rideId}`).update({
      status: 'CANCELLED',
      timestamp: Date.now(),
    });

    return {
      success: true,
      rideId: data.rideId,
      status: 'CANCELLED',
      cancellationFee,
      cancelledBy: caller.uid,
    };
  }
);
