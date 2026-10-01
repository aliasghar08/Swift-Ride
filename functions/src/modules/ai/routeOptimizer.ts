import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { getGeminiModel, logger, AI_CONFIG } from '../../config/ai';
import { assertRole } from '../../middleware/auth';

export interface RouteOptimizerRequest {
  rideId?: string;
  pickup: { lat: number; lng: number; address?: string };
  dropoff: { lat: number; lng: number; address?: string };
  distanceKm?: number;
  durationMinutes?: number;
  trafficCondition?: string;
}

export async function processRouteOptimization(driverId: string, data: RouteOptimizerRequest) {
  const { pickup, dropoff, distanceKm = 8.5, durationMinutes = 18, trafficCondition = 'MODERATE', rideId } = data;

  if (!pickup || !dropoff) {
    throw new HttpsError('invalid-argument', 'Pickup and Dropoff locations are required.');
  }

  logger.info({ driverId, rideId, distanceKm }, 'Optimizing route with AI');

  const prompt = `
You are a route navigation and traffic intelligence assistant for ride-hailing drivers on SwiftRide.
Analyze the trip parameters and recommend optimal routing strategies:

Trip:
- Pickup: ${pickup.address || `${pickup.lat}, ${pickup.lng}`}
- Destination: ${dropoff.address || `${dropoff.lat}, ${dropoff.lng}`}
- Direct distance: ${distanceKm} km
- Baseline estimate: ${durationMinutes} mins
- Traffic condition: ${trafficCondition}

Provide routing advice in valid JSON format:
{
  "suggestedDeparture": "Depart immediately without detour",
  "routePreference": "Take Main Arterial Parkway rather than congested inner city core",
  "warnings": [
    "Construction slowdown near 4th interchange lane taper",
    "School zone speed enforcement active during morning drop-off"
  ],
  "estimatedSavingsMinutes": 3,
  "confidence": 0.88
}
Strictly output JSON only.
`;

  let result: {
    suggestedDeparture: string;
    routePreference: string;
    warnings: string[];
    estimatedSavingsMinutes: number;
    confidence: number;
  };

  try {
    const model = getGeminiModel(AI_CONFIG.MAX_OUTPUT_TOKENS_INSIGHT, 'You are an urban traffic dispatcher and navigation optimizer.');
    const response = await model.generateContent(prompt);
    const cleaned = response.response.text().trim().replace(/^```json\s*/i, '').replace(/```\s*$/i, '');
    result = JSON.parse(cleaned);
  } catch (err: any) {
    logger.warn({ err: err?.message, driverId }, 'Route optimizer Gemini fallback applied');
    result = {
      suggestedDeparture: 'Depart immediately via recommended GPS corridor',
      routePreference: 'Stick to ring road / express lanes to bypass local signal congestion',
      warnings: ['Moderate congestion approaching key junctions', 'Watch for sudden lane merges near ramp exits'],
      estimatedSavingsMinutes: 2,
      confidence: 0.85,
    };
  }

  // Save insight
  const insightRef = await db.collection(APP_CONSTANTS.COLLECTIONS.AI_INSIGHTS).add({
    userId: driverId,
    type: 'ROUTE_OPTIMIZATION',
    content: `${result.routePreference}. ${result.suggestedDeparture}.`,
    metadata: {
      rideId,
      pickup,
      dropoff,
      warnings: result.warnings,
      estimatedSavingsMinutes: result.estimatedSavingsMinutes,
      confidence: result.confidence,
    },
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    id: insightRef.id,
    ...result,
  };
}

/**
 * Callable Cloud Function: routeOptimizer
 * Enforces App Check and Driver role.
 */
export const routeOptimizer = onCall(
  {
    region: APP_CONSTANTS.REGION,
    enforceAppCheck: true,
    memory: '512MiB',
    timeoutSeconds: 30,
  },
  async (request) => {
    const user = await assertRole(request, ['driver', 'admin']);
    return processRouteOptimization(user.uid, request.data || {});
  }
);
