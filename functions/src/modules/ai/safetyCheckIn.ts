import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { db, messaging } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { getGeminiModel, logger, AI_CONFIG } from '../../config/ai';
import { assertAuthenticated } from '../../middleware/auth';

export interface SafetyCheckInData {
  rideId: string;
  flagType: 'LONG_STOP' | 'ROUTE_DEVIATION' | 'UNEXPECTED_STOP' | 'EARLY_END';
  durationSeconds?: number;
  deviationMeters?: number;
  currentSpeedKmh?: number;
  location?: { lat: number; lng: number };
}

export async function processSafetyCheckIn(data: SafetyCheckInData) {
  const { rideId, flagType, durationSeconds = 180, deviationMeters = 350, currentSpeedKmh = 0 } = data;
  logger.info({ rideId, flagType }, 'Executing AI safety check-in');

  const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(rideId);
  const rideDoc = await rideRef.get();

  if (!rideDoc.exists) {
    throw new HttpsError('not-found', `Ride with id ${rideId} does not exist.`);
  }

  const ride = rideDoc.data()!;
  const riderId = ride.riderId;
  const driverId = ride.driverId;

  // Build prompt for Gemini 3.8 Flash
  const prompt = `
You are a safety assistant for a ride-hailing app. A ride has triggered a safety check.
Generate a brief, non-alarming check-in message.

Context:
- Ride status: ${ride.status || 'IN_PROGRESS'}
- Flag type: ${flagType}
- Time since last movement: ${durationSeconds} seconds
- Route deviation: ${deviationMeters} meters
- Current speed: ${currentSpeedKmh} km/h

The message must be 1-2 sentences, friendly, courteous, non-alarming, and clearly ask if everything is okay with an invitation to respond.
Do NOT use markdown, quotes, or JSON formatting. Just output the clean message text.
`;

  let checkInMessage: string;

  try {
    const model = getGeminiModel(AI_CONFIG.MAX_OUTPUT_TOKENS_CHAT, 'You are an empathetic, calm, and reassuring safety assistant.');
    const response = await model.generateContent(prompt);
    checkInMessage = response.response.text().trim();
  } catch (err: any) {
    logger.warn({ err: err?.message, rideId }, 'Gemini call failed for safety check-in, using safe fallback');
    switch (flagType) {
      case 'LONG_STOP':
      case 'UNEXPECTED_STOP':
        checkInMessage = 'We noticed your ride has been stopped for a little while. Is everything going smoothly, or do you need any assistance?';
        break;
      case 'ROUTE_DEVIATION':
        checkInMessage = "We noticed an unexpected change in your route. Please confirm you're safe or let us know if you need help.";
        break;
      default:
        checkInMessage = 'SwiftRide Safety Check: Everything looking good on your trip? Tap to let us know.';
        break;
    }
  }

  // Update ride document in Firestore so real-time listeners trigger
  await rideRef.update({
    safetyFlags: admin.firestore.FieldValue.arrayUnion(flagType),
    safetyCheckMessage: checkInMessage,
    safetyCheckActive: true,
    lastSafetyCheckAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Record in ai_insights collection for rider & driver history
  await db.collection(APP_CONSTANTS.COLLECTIONS.AI_INSIGHTS).add({
    userId: riderId,
    type: 'SAFETY_CHECK',
    content: checkInMessage,
    metadata: {
      rideId,
      flagType,
      durationSeconds,
      deviationMeters,
      resolved: false,
    },
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Dispatch push notifications to rider and driver
  const recipientIds = [riderId, driverId].filter(Boolean);
  for (const uid of recipientIds) {
    try {
      const userSnap = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(uid).get();
      const token = userSnap.data()?.fcmToken;
      if (token) {
        await messaging.send({
          token,
          notification: {
            title: 'SwiftRide Safety Check',
            body: checkInMessage,
          },
          data: {
            type: 'SAFETY_CHECK_ALERT',
            rideId,
            flagType,
            message: checkInMessage,
          },
        });
      }
    } catch (pushErr: any) {
      logger.warn({ uid, error: pushErr?.message }, 'Failed to deliver safety push notification');
    }
  }

  return {
    success: true,
    rideId,
    flagType,
    message: checkInMessage,
  };
}

/**
 * Callable function: safetyCheckIn
 * Enforces App Check and valid user session.
 */
export const safetyCheckIn = onCall(
  {
    region: APP_CONSTANTS.REGION,
    enforceAppCheck: true,
    memory: '512MiB',
    timeoutSeconds: 30,
  },
  async (request) => {
    await assertAuthenticated(request);
    const { rideId, flagType, durationSeconds, deviationMeters, currentSpeedKmh } = request.data || {};

    if (!rideId || !flagType) {
      throw new HttpsError('invalid-argument', 'rideId and flagType are required parameters.');
    }

    return processSafetyCheckIn({
      rideId,
      flagType,
      durationSeconds,
      deviationMeters,
      currentSpeedKmh,
    });
  }
);
