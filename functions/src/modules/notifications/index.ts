import * as admin from 'firebase-admin';
import { db, messaging } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';

export interface SwiftRidePushPayload {
  title: string;
  body: string;
  type:
    | 'NEW_RIDE_REQUEST'
    | 'COUNTER_OFFER'
    | 'OFFER_ACCEPTED'
    | 'DRIVER_ARRIVED'
    | 'SAFETY_ALERT'
    | 'RIDE_REQUEST'
    | 'RIDE_STATUS_UPDATE'
    | 'SOS';
  rideId: string;
  extraData?: Record<string, string>;
}

export async function sendPushToUser(
  uid: string,
  payload: SwiftRidePushPayload
): Promise<void> {
  try {
    const userDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(uid).get();
    let tokens: string[] = userDoc.data()?.fcmTokens ?? [];

    if (tokens.length === 0) {
      const driverDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(uid).get();
      tokens = driverDoc.data()?.fcmTokens ?? [];
    }

    if (tokens.length === 0) return;

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: {
        type: payload.type,
        rideId: payload.rideId,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        ...(payload.extraData ?? {}),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'swift_ride_dispatch',
          sound: 'default',
          priority: 'max',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            'content-available': 1,
          },
        },
      },
    };

    const response = await messaging.sendEachForMulticast(message);

    // Prune expired/uninstalled tokens automatically
    const invalidTokens: string[] = [];
    response.responses.forEach((res, idx) => {
      if (
        !res.success &&
        (res.error?.code === 'messaging/registration-token-not-registered' ||
          res.error?.code === 'messaging/invalid-registration-token')
      ) {
        invalidTokens.push(tokens[idx]);
      }
    });

    if (invalidTokens.length > 0) {
      const userRef = db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(uid);
      await userRef.update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      }).catch(() => {});

      const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(uid);
      await driverRef.update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      }).catch(() => {});
    }
  } catch (err) {
    console.warn(`[PushNotification] Failed to send push to user ${uid}:`, err);
  }
}

export async function sendPushToDrivers(
  driverIds: string[],
  payload: SwiftRidePushPayload
): Promise<void> {
  await Promise.all(driverIds.map((driverId) => sendPushToUser(driverId, payload)));
}

// Backward-compatible wrapper for existing triggers
export async function sendNotificationToUser(
  userId: string,
  payload: { title: string; body: string; data?: Record<string, string> }
): Promise<void> {
  const typeStr = (payload.data?.type as any) || 'RIDE_STATUS_UPDATE';
  const rideIdStr = payload.data?.rideId || '';
  await sendPushToUser(userId, {
    title: payload.title,
    body: payload.body,
    type: typeStr,
    rideId: rideIdStr,
    extraData: payload.data,
  });
}

export async function notifyDriversOfRide(
  driverIds: string[],
  rideId: string,
  pickupAddress: string,
  offeredFare: number,
  bookedSeats: number = 1,
  totalSeats: number = 4
): Promise<void> {
  const emptySeats = Math.max(0, totalSeats - bookedSeats);
  if (emptySeats <= 0) return;

  const title = 'New SwiftRide Request Nearby!';
  const body = `Fare offer: $${offeredFare.toFixed(2)} - Pickup: ${pickupAddress} (${emptySeats} seat${emptySeats === 1 ? '' : 's'} available)`;

  const payload: SwiftRidePushPayload = {
    title,
    body,
    type: 'NEW_RIDE_REQUEST',
    rideId,
    extraData: {
      offeredFare: offeredFare.toString(),
      bookedSeats: bookedSeats.toString(),
      totalSeats: totalSeats.toString(),
      emptySeats: emptySeats.toString(),
    },
  };

  await sendPushToDrivers(driverIds, payload);
}
