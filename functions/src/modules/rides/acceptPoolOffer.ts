import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { sendNotificationToUser } from '../notifications';
import { z } from 'zod';

const AcceptPoolOfferSchema = z.object({
  rideId: z.string().min(1),
  parentRideId: z.string().min(1),
});

export const acceptPoolOffer = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const { rideId, parentRideId } = validateInput(AcceptPoolOfferSchema, request.data);

    const parentRideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(parentRideId);
    const incomingRideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(rideId);

    const result = await db.runTransaction(async (transaction) => {
      const [parentDoc, incomingDoc] = await Promise.all([
        transaction.get(parentRideRef),
        transaction.get(incomingRideRef),
      ]);

      if (!parentDoc.exists) {
        throw new HttpsError('not-found', 'Parent active ride not found.');
      }
      if (!incomingDoc.exists) {
        throw new HttpsError('not-found', 'Incoming ride request not found.');
      }

      const parentData = parentDoc.data()!;
      const incomingData = incomingDoc.data()!;

      if (parentData.driverId !== caller.uid && caller.role !== 'admin') {
        throw new HttpsError('permission-denied', 'Only the assigned driver can accept a pooled co-rider.');
      }

      if (!['ACCEPTED', 'DRIVER_ARRIVED', 'IN_PROGRESS'].includes(parentData.status)) {
        throw new HttpsError('failed-precondition', `Parent ride status ${parentData.status} cannot accept pooled co-riders.`);
      }

      if (incomingData.status !== 'REQUESTED') {
        throw new HttpsError('failed-precondition', `Incoming ride is already ${incomingData.status}.`);
      }

      const incomingSeats = incomingData.bookedSeats ?? 1;
      const currentRemaining = parentData.remainingSeats !== undefined
        ? parentData.remainingSeats
        : Math.max(0, 4 - (parentData.bookedSeats ?? 1));

      if (currentRemaining < incomingSeats) {
        throw new HttpsError('failed-precondition', `Insufficient vehicle seats (${currentRemaining} available, ${incomingSeats} requested).`);
      }

      // Build ordered waypoints
      const existingWaypoints: Array<Record<string, any>> = Array.isArray(parentData.waypoints)
        ? [...parentData.waypoints]
        : [];

      // If no waypoints exist yet, seed with parent dropoff
      if (existingWaypoints.length === 0 && parentData.dropoff?.geopoint) {
        existingWaypoints.push({
          rideId: parentRideId,
          type: 'dropoff',
          lat: parentData.dropoff.geopoint.latitude,
          lng: parentData.dropoff.geopoint.longitude,
          address: parentData.dropoff.address || 'Destination',
          pin: parentData.pin ?? '1234',
          completed: false,
        });
      }

      const newPickupWaypoint = {
        rideId,
        type: 'pickup',
        lat: incomingData.pickup.geopoint.latitude,
        lng: incomingData.pickup.geopoint.longitude,
        address: incomingData.pickup.address || 'Pickup Point',
        pin: incomingData.pin ?? '1234',
        completed: false,
      };

      const newDropoffWaypoint = {
        rideId,
        type: 'dropoff',
        lat: incomingData.dropoff.geopoint.latitude,
        lng: incomingData.dropoff.geopoint.longitude,
        address: incomingData.dropoff.address || 'Dropoff Point',
        pin: incomingData.pin ?? '1234',
        completed: false,
      };

      // Ordered: New pickup is inserted first, new dropoff is inserted before or after final dropoff
      existingWaypoints.unshift(newPickupWaypoint);
      existingWaypoints.push(newDropoffWaypoint);

      // 1. Update parent ride with decremented seats and updated waypoints
      transaction.update(parentRideRef, {
        remainingSeats: currentRemaining - incomingSeats,
        waypoints: existingWaypoints,
        updatedAt: FieldValue.serverTimestamp(),
      });

      // 2. Accept incoming ride and link parent
      transaction.update(incomingRideRef, {
        driverId: caller.uid,
        parentPoolRideId: parentRideId,
        acceptedFare: incomingData.offeredFare,
        status: 'ACCEPTED',
        acceptedAt: FieldValue.serverTimestamp(),
      });

      return {
        driverId: caller.uid,
        acceptedFare: incomingData.offeredFare,
        riderId: incomingData.riderId,
      };
    });

    // Sync to RTDB
    await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${rideId}`).set({
      driverId: result.driverId,
      parentPoolRideId: parentRideId,
      status: 'ACCEPTED',
      timestamp: Date.now(),
      heading: 0,
      speed: 0,
    });

    // Notify Rider
    await sendNotificationToUser(result.riderId, {
      title: 'Shared Ride Matched! 🚗',
      body: `An en-route driver accepted your pooled ride for PKR ${result.acceptedFare}!`,
      data: {
        rideId,
        parentPoolRideId: parentRideId,
        status: 'ACCEPTED',
        type: 'OFFER_ACCEPTED',
      },
    });

    return {
      success: true,
      rideId,
      parentRideId,
      driverId: result.driverId,
      acceptedFare: result.acceptedFare,
      status: 'ACCEPTED',
    };
  }
);
