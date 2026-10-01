import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const AcceptOfferSchema = z.object({
  rideId: z.string().min(1),
  offerId: z.string().min(1),
});

export const acceptOffer = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const { rideId, offerId } = validateInput(AcceptOfferSchema, request.data);

    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(rideId);
    const offerRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDE_OFFERS).doc(offerId);

    const result = await db.runTransaction(async (transaction) => {
      const [rideDoc, offerDoc] = await Promise.all([
        transaction.get(rideRef),
        transaction.get(offerRef),
      ]);

      if (!rideDoc.exists) {
        throw new HttpsError('not-found', 'Ride not found.');
      }
      if (!offerDoc.exists) {
        throw new HttpsError('not-found', 'Ride offer not found.');
      }

      const rideData = rideDoc.data()!;
      const offerData = offerDoc.data()!;

      if (rideData.riderId !== caller.uid && caller.role !== 'admin') {
        throw new HttpsError('permission-denied', 'Only the rider who requested the ride can accept an offer.');
      }

      if (rideData.status !== 'REQUESTED') {
        throw new HttpsError('failed-precondition', `Ride is already ${rideData.status}.`);
      }

      if (offerData.rideId !== rideId) {
        throw new HttpsError('invalid-argument', 'Offer does not match ride.');
      }

      if (offerData.status !== 'PENDING') {
        throw new HttpsError('failed-precondition', `Offer is already ${offerData.status}.`);
      }

      // 1. Update ride
      transaction.update(rideRef, {
        driverId: offerData.driverId,
        acceptedFare: offerData.counterFare,
        status: 'ACCEPTED',
        acceptedAt: FieldValue.serverTimestamp(),
      });

      // 2. Mark this offer ACCEPTED
      transaction.update(offerRef, {
        status: 'ACCEPTED',
        resolvedAt: FieldValue.serverTimestamp(),
      });

      return {
        driverId: offerData.driverId,
        acceptedFare: offerData.counterFare,
      };
    });

    // 3. Mark other offers EXPIRED outside transaction
    const otherOffers = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDE_OFFERS)
      .where('rideId', '==', rideId)
      .where('status', '==', 'PENDING')
      .get();

    const batch = db.batch();
    otherOffers.forEach((doc) => {
      if (doc.id !== offerId) {
        batch.update(doc.ref, { status: 'EXPIRED' });
      }
    });
    await batch.commit();

    // 4. Initialize RTDB tracking node
    await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${rideId}`).set({
      driverId: result.driverId,
      status: 'ACCEPTED',
      timestamp: Date.now(),
      heading: 0,
      speed: 0,
    });

    return {
      success: true,
      rideId,
      driverId: result.driverId,
      acceptedFare: result.acceptedFare,
      status: 'ACCEPTED',
    };
  }
);
