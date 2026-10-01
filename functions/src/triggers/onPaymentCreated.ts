import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { db } from '../config/firebase';
import { APP_CONSTANTS } from '../config/constants';
import { FieldValue } from 'firebase-admin/firestore';

export const onPaymentCreated = onDocumentCreated(
  {
    document: `${APP_CONSTANTS.COLLECTIONS.PAYMENTS}/{paymentId}`,
    region: APP_CONSTANTS.REGION,
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    if (data.status === 'succeeded' && data.rideId) {
      // Mark ride payment settled
      await db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId).update({
        paymentStatus: 'paid',
        paidAt: FieldValue.serverTimestamp(),
      });
    }
  }
);

export const onDriverDocUploaded = onDocumentCreated(
  {
    document: `${APP_CONSTANTS.COLLECTIONS.DRIVERS}/{driverId}/documents/{docId}`,
    region: APP_CONSTANTS.REGION,
  },
  async (event) => {
    const driverId = event.params.driverId;
    console.log(`New verification document uploaded for driver: ${driverId}. Queueing admin review.`);

    // Flag driver profile as having documents submitted for review
    await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(driverId).update({
      hasSubmittedDocuments: true,
      documentsUpdatedAt: FieldValue.serverTimestamp(),
    });
  }
);
