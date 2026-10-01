import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const UpdateRideStatusSchema = z.object({
  rideId: z.string().min(1),
  status: z.enum(['DRIVER_ARRIVED', 'IN_PROGRESS', 'COMPLETED']),
  pin: z.string().length(4).optional(),
});

export const updateRideStatus = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(UpdateRideStatusSchema, request.data);

    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId);
    const rideDoc = await rideRef.get();

    if (!rideDoc.exists) {
      throw new HttpsError('not-found', 'Ride not found.');
    }

    const rideData = rideDoc.data()!;

    // Driver verification check
    if (rideData.driverId !== caller.uid && caller.role !== 'admin') {
      throw new HttpsError('permission-denied', 'Only the assigned driver can update this ride status.');
    }

    const currentStatus = rideData.status;

    // Validate state transitions
    if (data.status === 'DRIVER_ARRIVED') {
      if (currentStatus !== 'ACCEPTED') {
        throw new HttpsError('failed-precondition', `Cannot transition from ${currentStatus} to DRIVER_ARRIVED.`);
      }
    } else if (data.status === 'IN_PROGRESS') {
      if (currentStatus !== 'DRIVER_ARRIVED' && currentStatus !== 'ACCEPTED') {
        throw new HttpsError('failed-precondition', `Cannot transition from ${currentStatus} to IN_PROGRESS.`);
      }
      // PIN verification is mandatory to start ride and prevent wrong-car incidents
      if (!data.pin || data.pin !== rideData.pin) {
        throw new HttpsError('permission-denied', 'Incorrect 4-digit verification PIN.');
      }
    } else if (data.status === 'COMPLETED') {
      if (currentStatus !== 'IN_PROGRESS') {
        throw new HttpsError('failed-precondition', `Cannot transition from ${currentStatus} to COMPLETED.`);
      }
    }

    const updates: Record<string, unknown> = {
      status: data.status,
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (data.status === 'IN_PROGRESS') {
      updates.startedAt = FieldValue.serverTimestamp();
      updates.pinVerified = true;
    } else if (data.status === 'COMPLETED') {
      updates.completedAt = FieldValue.serverTimestamp();
      updates.paymentStatus = 'paid';

      // Increment ride counters for both rider and driver
      const riderRef = db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(rideData.riderId);
      const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(rideData.driverId);
      await Promise.all([
        riderRef.update({ totalRides: FieldValue.increment(1) }),
        driverRef.update({ totalRides: FieldValue.increment(1) }),
      ]);
    }

    await rideRef.update(updates);

    // Sync status to RTDB ride_tracking node
    await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${data.rideId}`).update({
      status: data.status,
      timestamp: Date.now(),
    });

    return {
      success: true,
      rideId: data.rideId,
      status: data.status,
    };
  }
);
