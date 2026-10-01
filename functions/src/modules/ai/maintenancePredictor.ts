import { onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import { db, messaging } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { getGeminiModel, logger, AI_CONFIG } from '../../config/ai';
import { assertRole } from '../../middleware/auth';

export interface MaintenancePredictionResult {
  id: string;
  driverId: string;
  insight: string;
  maintenanceItems: string[];
  urgency: 'LOW' | 'MEDIUM' | 'HIGH';
  nextDueInKm: number;
  totalKmLogged: number;
}

export async function processMaintenancePrediction(driverId: string): Promise<MaintenancePredictionResult> {
  logger.info({ driverId }, 'Running predictive maintenance analysis');

  // 1. Fetch past 30 days completed rides to calculate mileage
  const thirtyDaysAgo = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
  );

  const ridesSnapshot = await db
    .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
    .where('driverId', '==', driverId)
    .where('status', '==', 'COMPLETED')
    .where('createdAt', '>=', thirtyDaysAgo)
    .get();

  let totalKm = 0;
  ridesSnapshot.forEach((doc) => {
    const km = Number(doc.data()?.distanceKm) || 4.5;
    totalKm += km;
  });

  const tripCount = ridesSnapshot.size;
  // Estimate commute + positioning deadhead factor (1.35x)
  const estimatedTotalKm = Math.round(totalKm * 1.35);

  const prompt = `
You are a vehicle maintenance expert for ride-hailing drivers on the SwiftRide platform.
Analyze the vehicle usage metrics and determine predictive maintenance needs.

Usage metrics (past 30 days):
- Total commercial ride distance: ${totalKm.toFixed(1)} km
- Total estimated fleet mileage (including deadhead): ${estimatedTotalKm} km
- Completed passenger trips: ${tripCount}

Provide predictive maintenance advice in strict JSON format:
{
  "insight": "Concise 2-sentence summary of vehicle status and recommended servicing",
  "maintenanceItems": [
    "Maintenance task 1 (e.g. Tire rotation / Brake pad check)",
    "Maintenance task 2"
  ],
  "urgency": "LOW",
  "nextDueInKm": 1500
}
Values for urgency: "LOW", "MEDIUM", or "HIGH".
`;

  let parsed: { insight: string; maintenanceItems: string[]; urgency: 'LOW' | 'MEDIUM' | 'HIGH'; nextDueInKm: number };

  try {
    const model = getGeminiModel(AI_CONFIG.MAX_OUTPUT_TOKENS_INSIGHT, 'You are a certified automotive safety and preventative maintenance expert.');
    const response = await model.generateContent(prompt);
    const cleaned = response.response.text().trim().replace(/^```json\s*/i, '').replace(/```\s*$/i, '');
    parsed = JSON.parse(cleaned);
  } catch (err: any) {
    logger.warn({ err: err?.message, driverId }, 'Gemini maintenance call failed, applying heuristic rules');
    const urgency = estimatedTotalKm > 2500 ? 'MEDIUM' : 'LOW';
    parsed = {
      insight: `Your vehicle logged ${estimatedTotalKm} km over the past 30 days. Regular oil viscosity checks and brake lining inspections ensure passenger comfort and safety.`,
      maintenanceItems: [
        'Inspect front and rear tire tread depth and check cold inflation pressures',
        'Verify engine synthetic oil levels and windshield washer fluid reservoir',
      ],
      urgency,
      nextDueInKm: Math.max(500, 3000 - (estimatedTotalKm % 3000)),
    };
  }

  // Save to ai_insights
  const insightRef = await db.collection(APP_CONSTANTS.COLLECTIONS.AI_INSIGHTS).add({
    userId: driverId,
    type: 'MAINTENANCE_ALERT',
    content: parsed.insight,
    metadata: {
      maintenanceItems: parsed.maintenanceItems,
      urgency: parsed.urgency,
      nextDueInKm: parsed.nextDueInKm,
      totalKmLogged: estimatedTotalKm,
      analyzedTrips: tripCount,
    },
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Send push notification
  try {
    const userDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(driverId).get();
    const token = userDoc.data()?.fcmToken;
    if (token) {
      await messaging.send({
        token,
        notification: {
          title: 'SwiftRide Vehicle Health',
          body: parsed.insight,
        },
        data: {
          type: 'AI_MAINTENANCE_ALERT',
          insightId: insightRef.id,
          urgency: parsed.urgency,
        },
      });
    }
  } catch (pushErr: any) {
    logger.warn({ driverId, error: pushErr?.message }, 'Failed to send maintenance push notification');
  }

  return {
    id: insightRef.id,
    driverId,
    insight: parsed.insight,
    maintenanceItems: parsed.maintenanceItems,
    urgency: parsed.urgency,
    nextDueInKm: parsed.nextDueInKm,
    totalKmLogged: estimatedTotalKm,
  };
}

/**
 * Callable Cloud Function: predictVehicleMaintenance
 * Enforces App Check and Driver role.
 */
export const predictVehicleMaintenance = onCall(
  {
    region: APP_CONSTANTS.REGION,
    enforceAppCheck: true,
    memory: '512MiB',
    timeoutSeconds: 45,
  },
  async (request) => {
    const user = await assertRole(request, ['driver', 'admin']);
    return processMaintenancePrediction(user.uid);
  }
);

/**
 * Scheduled Cloud Function: weeklyMaintenanceSchedule
 * Runs every Monday morning at 8:00 AM.
 */
export const weeklyMaintenanceSchedule = onSchedule(
  {
    region: APP_CONSTANTS.REGION,
    schedule: '0 8 * * 1',
    timeZone: 'UTC',
    memory: '512MiB',
  },
  async () => {
    logger.info('Executing weekly driver vehicle maintenance predictions');
    const driversSnapshot = await db
      .collection(APP_CONSTANTS.COLLECTIONS.DRIVERS)
      .where('status', '==', 'APPROVED')
      .limit(50)
      .get();

    for (const driver of driversSnapshot.docs) {
      try {
        await processMaintenancePrediction(driver.id);
      } catch (err: any) {
        logger.error({ driverId: driver.id, err: err?.message }, 'Weekly maintenance check failed for driver');
      }
    }
    logger.info({ processedCount: driversSnapshot.size }, 'Weekly maintenance check completed');
  }
);
