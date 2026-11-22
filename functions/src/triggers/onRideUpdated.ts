import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { db, rtdb } from '../config/firebase';
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
        let notifType = 'RIDE_STATUS_UPDATE';
        if (after.status === 'ACCEPTED') {
          msg = `A driver accepted your offer for $${after.acceptedFare}!`;
          notifType = 'OFFER_ACCEPTED';
        } else if (after.status === 'DRIVER_ARRIVED') {
          msg = `Your driver has arrived at the pickup location. Share PIN ${after.pin} to start!`;
          notifType = 'DRIVER_ARRIVED';
        } else if (after.status === 'IN_PROGRESS') {
          msg = 'Your trip is now in progress. Safe travels!';
        } else if (after.status === 'COMPLETED') {
          msg = `Trip completed! Thank you for riding with SwiftRide.`;
        } else if (after.status === 'CANCELLED') {
          msg = 'Your ride has been cancelled.';
        }

        if (msg) {
          await sendNotificationToUser(after.riderId, {
            title: notifType === 'DRIVER_ARRIVED' ? 'Driver Arrived! 📍' : 'SwiftRide Status Update',
            body: msg,
            data: { rideId, status: after.status, type: notifType },
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

      // Log Anonymized ML Training Outcome Telemetry (Zero PII)
      // When ride concludes (COMPLETED, CANCELLED, or EXPIRED)
      if (['COMPLETED', 'CANCELLED'].includes(after.status)) {
        try {
          const vehicleTierMap: Record<string, number> = {
            bike: 0,
            rikshaw: 1,
            rickshaw: 1,
            car_economy: 2,
            car_ac: 3,
            comfort: 4,
            car: 3,
          };
          const vehicleTier = vehicleTierMap[after.vehicleType] ?? 3;
          const distanceKm = typeof after.distanceKm === 'number' ? after.distanceKm : 5.0;
          const durationMin = typeof after.durationMin === 'number' ? after.durationMin : 15.0;
          const initialOfferPkr = typeof after.offeredFare === 'number' ? after.offeredFare : 300.0;
          const finalAgreedFarePkr = typeof after.acceptedFare === 'number' ? after.acceptedFare : initialOfferPkr;
          const wasHaggled = after.acceptedFare !== undefined && Math.abs(after.acceptedFare - initialOfferPkr) > 1.0;

          // Estimate congestion ratio from duration vs expected free-flow
          const expectedFreeFlowMin = (distanceKm / 35.0) * 60.0;
          const congestionRatio = Math.min(2.4, Math.max(1.0, durationMin / Math.max(1.0, expectedFreeFlowMin)));

          // Infer acceptedWithinSec if timestamps available
          let acceptedWithinSec = 45;
          if (after.acceptedAt && after.createdAt) {
            const createdMs = after.createdAt.toMillis ? after.createdAt.toMillis() : Date.parse(after.createdAt);
            const acceptedMs = after.acceptedAt.toMillis ? after.acceptedAt.toMillis() : Date.parse(after.acceptedAt);
            if (!isNaN(createdMs) && !isNaN(acceptedMs) && acceptedMs >= createdMs) {
              acceptedWithinSec = Math.round((acceptedMs - createdMs) / 1000);
            }
          }

          const outcomeRef = db.collection(APP_CONSTANTS.COLLECTIONS.ML_TRAINING_OUTCOMES).doc(rideId);
          await outcomeRef.set({
            distanceKm,
            durationMin,
            congestionRatio: Math.round(congestionRatio * 100) / 100,
            vehicleTier,
            roadCondition: 1, // Default urban normal
            acEnabled: vehicleTier >= 2 ? 1 : 0,
            bookedSeats: after.bookedSeats ?? 1,
            fuelPricePkr: 285.0, // Baseline PKR petrol reference
            initialOfferPkr,
            finalAgreedFarePkr,
            acceptedWithinSec,
            wasHaggled,
            finalStatus: after.status,
            timestamp: FieldValue.serverTimestamp(),
          });
        } catch (mlErr) {
          console.warn('[MLTelemetry] Error logging training outcome:', mlErr);
        }
      }
    }
  }
);
