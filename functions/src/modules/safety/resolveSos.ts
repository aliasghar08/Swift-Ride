import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const ResolveSosSchema = z.object({
  eventId: z.string().min(1),
  note: z.string().max(500).optional(),
});

/**
 * Closes an open emergency alert.
 *
 * Nothing could resolve an alert before this: `safety_events` allowed update
 * only for admins, and no admin UI or function existed. So once an SOS fired it
 * stayed open permanently — the assigned driver's emergency banner never
 * cleared, and `getDashboardStats` counted it as unresolved forever.
 *
 * Permitted for the rider who raised it, the driver on that trip, or an admin.
 * The event is never deleted, so the record of the incident survives.
 */
export const resolveSos = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(ResolveSosSchema, request.data);

    const eventRef = db
      .collection(APP_CONSTANTS.COLLECTIONS.SAFETY_EVENTS)
      .doc(data.eventId);
    const eventSnap = await eventRef.get();

    if (!eventSnap.exists) {
      throw new HttpsError('not-found', 'That alert no longer exists.');
    }

    const event = eventSnap.data() as Record<string, unknown>;

    if (event.resolvedAt) {
      // Idempotent: two people closing the same alert is normal, not an error.
      return { success: true, alreadyResolved: true };
    }

    const isAdmin = caller.role === 'admin';
    // The trigger stores the raiser as `triggeredBy` (not `userId`).
    let permitted = event.triggeredBy === caller.uid;

    if (!permitted && !isAdmin) {
      // The driver on the trip may stand the alert down (they can see the rider
      // is safe in person). Anyone else may not.
      const rideId = String(event.rideId ?? '');
      if (rideId) {
        const rideSnap = await db
          .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
          .doc(rideId)
          .get();
        permitted = rideSnap.exists && rideSnap.data()?.driverId === caller.uid;
      }
    }

    if (!permitted && !isAdmin) {
      throw new HttpsError('permission-denied', 'You cannot close this alert.');
    }

    await eventRef.update({
      resolvedAt: FieldValue.serverTimestamp(),
      resolvedBy: caller.uid,
      resolvedByRole: isAdmin ? 'admin' : caller.role,
      ...(data.note ? { resolutionNote: data.note } : {}),
    });

    return { success: true, alreadyResolved: false };
  }
);
