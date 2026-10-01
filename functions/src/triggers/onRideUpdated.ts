import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { rtdb } from '../config/firebase';
import { APP_CONSTANTS } from '../config/constants';
import { sendNotificationToUser } from '../modules/notifications';

export const onRideUpdated = onDocumentUpdated(
  {
    document: `${APP_CONSTANTS.COLLECTIONS.RIDES}/{rideId}`,
    region: APP_CONSTANTS.REGION,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const rideId = event.params.rideId;

    if (before.status !== after.status) {
      console.log(`Ride ${rideId} transitioned from ${before.status} to ${after.status}`);

      // Sync status to RTDB ride_tracking node
      await rtdb.ref(`${APP_CONSTANTS.RTDB_NODES.RIDE_TRACKING}/${rideId}`).update({
        status: after.status,
        timestamp: Date.now(),
      });

      // Send push notification to rider
      if (after.riderId) {
        let msg = '';
        if (after.status === 'ACCEPTED') {
          msg = `A driver accepted your offer for $${after.acceptedFare}!`;
        } else if (after.status === 'DRIVER_ARRIVED') {
          msg = `Your driver has arrived at the pickup location. Share PIN ${after.pin} to start!`;
        } else if (after.status === 'IN_PROGRESS') {
          msg = 'Your trip is now in progress. Safe travels!';
        } else if (after.status === 'COMPLETED') {
          msg = `Trip completed! Thank you for riding with SwiftRide.`;
        } else if (after.status === 'CANCELLED') {
          msg = 'Your ride has been cancelled.';
        }

        if (msg) {
          await sendNotificationToUser(after.riderId, {
            title: 'SwiftRide Status Update',
            body: msg,
            data: { rideId, status: after.status },
          });
        }
      }

      // Send push notification to driver if ride cancelled
      if (after.driverId && after.status === 'CANCELLED') {
        await sendNotificationToUser(after.driverId, {
          title: 'Ride Cancelled',
          body: `Ride ${rideId} was cancelled by rider.`,
          data: { rideId, status: 'CANCELLED' },
        });
      }
    }
  }
);
