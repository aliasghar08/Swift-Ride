import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput, LatLngSchema } from '../../middleware/validation';
import { z } from 'zod';

const TriggerSosSchema = z.object({
  rideId: z.string().min(1),
  location: LatLngSchema,
  message: z.string().optional(),
});

export const triggerSos = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(TriggerSosSchema, request.data);

    const eventRef = db.collection(APP_CONSTANTS.COLLECTIONS.SAFETY_EVENTS).doc();
    const eventPayload = {
      rideId: data.rideId,
      triggeredBy: caller.uid,
      type: 'SOS',
      geopoint: data.location,
      metadata: {
        message: data.message || 'EMERGENCY SOS TRIGGERED',
        userRole: caller.role,
      },
      resolvedAt: null,
      createdAt: FieldValue.serverTimestamp(),
    };

    await eventRef.set(eventPayload);

    // Flag ride safety
    await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
      .doc(data.rideId)
      .update({
        safetyFlags: FieldValue.arrayUnion('SOS_TRIGGERED'),
        updatedAt: FieldValue.serverTimestamp(),
      });

    return {
      success: true,
      eventId: eventRef.id,
      emergencyNotice: 'Emergency SOS alert recorded. Dispatching safety notification.',
    };
  }
);
