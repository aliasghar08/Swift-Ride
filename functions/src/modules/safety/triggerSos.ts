import { onCall } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, messaging } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput, LatLngSchema } from '../../middleware/validation';
import { z } from 'zod';

const TriggerSosSchema = z.object({
  rideId: z.string().min(1),
  location: LatLngSchema,
  message: z.string().max(500).optional(),
});

/** Firestore `in` queries accept at most 30 values per query. */
const PHONE_QUERY_CHUNK = 30;

type RecipientReason = 'counterparty' | 'trusted_contact';

interface ReachableRecipient {
  uid: string;
  reason: RecipientReason;
  tokens: string[];
}

/**
 * Resolves which trusted contacts are actually reachable.
 *
 * A trusted contact is stored on the user document as a phone number. Because
 * push delivery requires the contact to have a SwiftRide account with a
 * registered FCM token, we resolve phone -> user -> fcmTokens. Contacts without
 * an account are reported back as unreachable rather than silently counted as
 * notified.
 */
async function resolveTrustedContacts(
  phones: string[],
  excludeUid: string
): Promise<{ recipients: ReachableRecipient[]; unreachablePhones: string[] }> {
  const recipients: ReachableRecipient[] = [];
  const unreachablePhones: string[] = [];

  for (let i = 0; i < phones.length; i += PHONE_QUERY_CHUNK) {
    const chunk = phones.slice(i, i + PHONE_QUERY_CHUNK);
    const snap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.USERS)
      .where('phone', 'in', chunk)
      .get();

    const matchedPhones = new Set<string>();
    snap.forEach((doc) => {
      const docData = doc.data();
      const tokens: string[] = Array.isArray(docData.fcmTokens) ? docData.fcmTokens : [];
      if (doc.id !== excludeUid && tokens.length > 0) {
        recipients.push({ uid: doc.id, reason: 'trusted_contact', tokens });
        matchedPhones.add(String(docData.phone));
      }
    });

    for (const phone of chunk) {
      if (!matchedPhones.has(phone)) unreachablePhones.push(phone);
    }
  }

  return { recipients, unreachablePhones };
}

export const triggerSos = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(TriggerSosSchema, request.data);

    const eventRef = db.collection(APP_CONSTANTS.COLLECTIONS.SAFETY_EVENTS).doc();
    await eventRef.set({
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
    });

    const rideRef = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).doc(data.rideId);
    const rideSnap = await rideRef.get();
    const ride = rideSnap.exists ? (rideSnap.data() as Record<string, any>) : {};

    if (rideSnap.exists) {
      await rideRef.update({
        safetyFlags: FieldValue.arrayUnion('SOS_TRIGGERED'),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // ---------------------------------------------------------------
    // Resolve everyone we can actually reach
    // ---------------------------------------------------------------
    const recipients = new Map<string, ReachableRecipient>();

    // 1. The other party on the trip (driver if the rider raised it, or vice versa).
    const counterpartyUid = caller.uid === ride.riderId ? ride.driverId : ride.riderId;
    if (counterpartyUid && counterpartyUid !== caller.uid) {
      const cpSnap = await db
        .collection(APP_CONSTANTS.COLLECTIONS.USERS)
        .doc(String(counterpartyUid))
        .get();
      const cpData = cpSnap.data();
      const tokens: string[] = Array.isArray(cpData?.fcmTokens) ? cpData!.fcmTokens : [];
      if (tokens.length > 0) {
        recipients.set(String(counterpartyUid), {
          uid: String(counterpartyUid),
          reason: 'counterparty',
          tokens,
        });
      }
    }

    // 2. The caller's trusted contacts.
    const callerSnap = await db
      .collection(APP_CONSTANTS.COLLECTIONS.USERS)
      .doc(caller.uid)
      .get();
    const callerData = callerSnap.data();
    const rawContacts = callerData?.trustedContacts;
    const trustedPhones: string[] = Array.isArray(rawContacts)
      ? rawContacts.filter((p: unknown): p is string => typeof p === 'string' && p.length > 0)
      : [];

    const { recipients: contactRecipients, unreachablePhones } = await resolveTrustedContacts(
      trustedPhones,
      caller.uid
    );

    for (const r of contactRecipients) {
      if (!recipients.has(r.uid)) recipients.set(r.uid, r);
    }

    // ---------------------------------------------------------------
    // Fan out the alert
    // ---------------------------------------------------------------
    const recipientList = [...recipients.values()];
    const allTokens = recipientList.flatMap((r) => r.tokens);

    let successCount = 0;
    let failureCount = 0;

    if (allTokens.length > 0) {
      const callerName = callerData?.fullName || 'A SwiftRide user';

      const response = await messaging.sendEachForMulticast({
        tokens: allTokens,
        notification: {
          title: '🚨 EMERGENCY SOS',
          body: `${callerName} triggered an emergency alert during a trip. Open SwiftRide now.`,
        },
        data: {
          type: 'SOS',
          rideId: data.rideId,
          eventId: eventRef.id,
          latitude: String(data.location.latitude),
          longitude: String(data.location.longitude),
        },
        android: {
          priority: 'high',
          notification: { channelId: 'swiftride_emergency', priority: 'max' },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default', badge: 1 } },
        },
      });

      successCount = response.successCount;
      failureCount = response.failureCount;
    }

    const notifiedUids = recipientList.map((r) => r.uid);

    await eventRef.update({
      dispatch: {
        recipientUids: notifiedUids,
        attempted: allTokens.length,
        delivered: successCount,
        failed: failureCount,
        unreachablePhones,
        dispatchedAt: FieldValue.serverTimestamp(),
      },
    });

    // An honest report. The client must NOT claim help is on the way if nobody
    // was actually reached.
    const reachedAnyone = successCount > 0;
    return {
      success: true,
      eventId: eventRef.id,
      delivered: successCount,
      failed: failureCount,
      notifiedContacts: notifiedUids.length,
      unreachablePhones,
      reachedAnyone,
      emergencyNotice: reachedAnyone
        ? `Emergency alert delivered to ${successCount} ${
            successCount === 1 ? 'person' : 'people'
          }.`
        : 'No one could be reached automatically. Call local emergency services now.',
    };
  }
);
