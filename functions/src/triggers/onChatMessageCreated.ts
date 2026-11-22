import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import { sendPushToUser } from '../modules/notifications';
import { APP_CONSTANTS } from '../config/constants';

export const onChatMessageCreated = onDocumentCreated(
  {
    document: `${APP_CONSTANTS.COLLECTIONS.RIDES}/{rideId}/messages/{messageId}`,
    region: APP_CONSTANTS.REGION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const msg = snap.data();
    const rideId = event.params.rideId;

    const rideDoc = await admin.firestore().collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(rideId).get();
    const ride = rideDoc.data();
    if (!ride) return;

    // Only allow chat during active ride lifecycle
    if (!['ACCEPTED', 'DRIVER_ARRIVED', 'IN_PROGRESS'].includes(ride.status)) return;

    const recipientUid = msg.senderId === ride.riderId ? ride.driverId : ride.riderId;
    if (!recipientUid) return;

    const senderLabel =
      msg.senderRole === 'driver'
        ? (ride.driverName || 'Your Driver')
        : (ride.riderName || 'Your Rider');

    await sendPushToUser(recipientUid, {
      title: `Message from ${senderLabel}`,
      body: msg.text,
      type: 'NEW_CHAT_MESSAGE',
      rideId,
      extraData: {
        messageId: event.params.messageId,
        senderRole: msg.senderRole,
      },
    });
  }
);
