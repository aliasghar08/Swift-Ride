import { messaging, db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';

export async function sendNotificationToUser(
  userId: string,
  payload: { title: string; body: string; data?: Record<string, string> }
): Promise<void> {
  try {
    const userDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(userId).get();
    const tokens: string[] = userDoc.data()?.fcmTokens || [];

    if (tokens.length === 0) return;

    await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data || {},
    });
  } catch (err) {
    console.warn(`Failed to send notification to user ${userId}:`, err);
  }
}

export async function notifyDriversOfRide(
  driverIds: string[],
  rideId: string,
  pickupAddress: string,
  offeredFare: number
): Promise<void> {
  for (const driverId of driverIds) {
    await sendNotificationToUser(driverId, {
      title: 'New SwiftRide Request Nearby!',
      body: `Fare offer: $${offeredFare.toFixed(2)} - Pickup: ${pickupAddress}`,
      data: {
        type: 'RIDE_REQUEST',
        rideId,
        offeredFare: offeredFare.toString(),
      },
    });
  }
}
