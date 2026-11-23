import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import * as crypto from 'crypto';
import { db, auth } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated, assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const RegisterUserSchema = z.object({
  fullName: z.string().min(2).max(100),
  phone: z.string().min(7).max(25),
  email: z.string().email().optional(),
  role: z.enum(['passenger', 'rider', 'driver']).default('passenger'),
  fcmToken: z.string().optional(),
});

export const registerUser = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(RegisterUserSchema, request.data);

    const userRef = db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(caller.uid);
    const existing = await userRef.get();

    const timestamp = FieldValue.serverTimestamp();
    const fcmTokens = data.fcmToken ? [data.fcmToken] : [];

    // Guarantee phone number matches cryptographically verified SMS token if available
    const tokenPhone = request.auth?.token?.phone_number as string | undefined;
    const finalPhone = tokenPhone || data.phone;

    if (!existing.exists) {
      await userRef.set({
        phone: finalPhone,
        email: data.email || null,
        fullName: data.fullName,
        role: data.role,
        rating: 5.0,
        totalRides: 0,
        fcmTokens,
        createdAt: timestamp,
        updatedAt: timestamp,
        location: null,
      });

      // Mint signed custom claims on ID token
      await auth.setCustomUserClaims(caller.uid, {
        role: data.role,
        admin: false,
        phone: finalPhone,
      });
    } else {
      await userRef.update({
        fullName: data.fullName,
        phone: finalPhone,
        email: data.email || null,
        updatedAt: timestamp,
        ...(data.fcmToken
          ? { fcmTokens: FieldValue.arrayUnion(data.fcmToken) }
          : {}),
      });

      // Refresh custom claims
      const currentClaims = (await auth.getUser(caller.uid)).customClaims || {};
      await auth.setCustomUserClaims(caller.uid, {
        ...currentClaims,
        role: data.role,
        phone: finalPhone,
      });
    }

    if (data.role === 'driver') {
      await ensureDriverDocumentExists(caller.uid, { phone: finalPhone, fullName: data.fullName });
    }

    return { success: true, userId: caller.uid, role: data.role };
  }
);

export const verifyOtp = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const userDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(caller.uid).get();

    return {
      success: true,
      uid: caller.uid,
      exists: userDoc.exists,
      user: userDoc.data() || null,
    };
  }
);

const SetUserRoleSchema = z.object({
  targetUserId: z.string().min(1),
  role: z.enum(['passenger', 'rider', 'driver', 'admin']),
});

async function ensureDriverDocumentExists(userId: string, data: { phone?: string; fullName?: string }) {
  const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(userId);
  const driverDoc = await driverRef.get();
  if (!driverDoc.exists) {
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);
    await driverRef.set({
      userId,
      licenseNumber: 'PK-LIC-' + userId.substring(0, 6).toUpperCase(),
      vehicleMake: 'Toyota',
      vehicleModel: 'Corolla Altis',
      vehiclePlate: 'LEA-786',
      vehicleColor: 'White',
      vehicleYear: 2022,
      vehicleType: 'sedan',
      hasAc: true,
      seats: 4,
      isVerified: true,
      isOnline: false,
      subscriptionStatus: 'ACTIVE',
      subscriptionExpiresAt: expiresAt,
      stripeAccountId: 'acct_mock_' + userId,
      payoutStatus: 'ACTIVE',
      rating: 5.0,
      totalRides: 0,
      totalEarnings: 0,
      currentLocation: {
        geopoint: {
          latitude: 31.5204,
          longitude: 74.3587,
        },
        geohash: 'ttnfgpc',
      },
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
}

export const setUserRole = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    await assertRole(request, ['admin']);
    const data = validateInput(SetUserRoleSchema, request.data);

    await auth.setCustomUserClaims(data.targetUserId, {
      role: data.role,
      admin: data.role === 'admin',
    });

    await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(data.targetUserId).update({
      role: data.role,
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (data.role === 'driver') {
      await ensureDriverDocumentExists(data.targetUserId, {});
    }

    return { success: true, targetUserId: data.targetUserId, role: data.role };
  }
);

export const deleteUserAccount = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const targetUid = caller.uid;

    // 1. Delete Firestore user, driver, and AI preferences documents
    await Promise.allSettled([
      db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(targetUid).delete(),
      db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(targetUid).delete(),
      db.collection('ai_preferences').doc(targetUid).delete(),
    ]);

    // 2. Delete Firebase Auth user record
    try {
      await auth.deleteUser(targetUid);
    } catch (e) {
      console.warn(`[deleteUserAccount] auth.deleteUser warning for ${targetUid}:`, e);
    }

    return { success: true, message: 'Account permanently deleted' };
  }
);

const RegisterTrustedDeviceSchema = z.object({
  deviceId: z.string().min(1).max(128),
  platform: z.string().optional().default('unknown'),
});

export const registerTrustedDevice = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);

    // Caller must have a verified phone number on their Firebase Auth token
    const tokenPhone = request.auth?.token?.phone_number as string | undefined;
    if (!tokenPhone) {
      throw new HttpsError('failed-precondition', 'Trusted device registration requires a phone-verified account.');
    }

    const data = validateInput(RegisterTrustedDeviceSchema, request.data);
    const rawToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');

    const deviceRef = db
      .collection(APP_CONSTANTS.COLLECTIONS.USERS)
      .doc(caller.uid)
      .collection('trustedDevices')
      .doc(data.deviceId);

    await deviceRef.set({
      deviceId: data.deviceId,
      tokenHash,
      phoneNumber: tokenPhone,
      platform: data.platform,
      createdAt: FieldValue.serverTimestamp(),
      lastUsedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      deviceId: data.deviceId,
      deviceTrustToken: rawToken,
    };
  }
);

const ResolveSocialSessionSchema = z.object({
  phoneNumber: z.string().optional(),
  deviceId: z.string().optional(),
  deviceTrustToken: z.string().optional(),
  provider: z.enum(['google', 'apple']),
});

function normalizeE164(raw?: string): string | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  let digits = trimmed.replace(/\D/g, '');
  if (digits.startsWith('9203')) {
    digits = '923' + digits.substring(4);
  } else if (digits.startsWith('03')) {
    digits = '923' + digits.substring(2);
  } else if (digits.startsWith('3') && digits.length === 10) {
    digits = '92' + digits;
  }
  if (digits.length < 9 || digits.length > 15) return null;
  return '+' + digits;
}

function maskPhoneNumber(phone: string): string {
  if (phone.length <= 6) return '***';
  const prefix = phone.substring(0, Math.min(6, phone.length - 4));
  const suffix = phone.substring(phone.length - 2);
  return `${prefix}*****${suffix}`;
}

export const resolveSocialSession = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const callerUid = caller.uid;
    const callerEmail = (request.auth?.token?.email as string | undefined) || null;
    const callerName = (request.auth?.token?.name as string | undefined) || '';
    const callerPhoto = (request.auth?.token?.picture as string | undefined) || null;
    const isEmailVerified = request.auth?.token?.email_verified === true;

    const data = validateInput(ResolveSocialSessionSchema, request.data);
    const normalizedCandidatePhone = normalizeE164(data.phoneNumber);

    const callerDocRef = db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(callerUid);
    const callerDoc = await callerDocRef.get();
    const callerData = callerDoc.data() || {};
    const existingCallerPhone = normalizeE164(callerData.phone as string | undefined);

    const targetPhone = normalizedCandidatePhone || existingCallerPhone;

    let targetUid: string | null = null;
    let targetUserData: any = null;

    if (targetPhone) {
      // 1. Check if an existing account owns this phone number in Firestore
      const usersByPhoneSnap = await db
        .collection(APP_CONSTANTS.COLLECTIONS.USERS)
        .where('phone', '==', targetPhone)
        .limit(1)
        .get();

      if (!usersByPhoneSnap.empty) {
        const foundDoc = usersByPhoneSnap.docs[0];
        targetUid = foundDoc.id;
        targetUserData = foundDoc.data();
      } else {
        // 2. Fallback check Firebase Auth getUserByPhoneNumber
        try {
          const authUser = await auth.getUserByPhoneNumber(targetPhone);
          if (authUser && authUser.uid) {
            targetUid = authUser.uid;
            const targetDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(targetUid).get();
            targetUserData = targetDoc.data() || null;
          }
        } catch (_) {
          // Phone not registered in Auth
        }
      }
    }

    // CASE A: Same UID or No Existing Account Found for Phone
    if (!targetUid || targetUid === callerUid) {
      const updates: Record<string, any> = {
        updatedAt: FieldValue.serverTimestamp(),
        linkedProviders: FieldValue.arrayUnion(data.provider),
      };

      if (callerEmail && !callerData.email) {
        updates.email = callerEmail;
      }
      if (callerPhoto && !callerData.photoUrl) {
        updates.photoUrl = callerPhoto;
      }
      if (callerName && (!callerData.fullName || callerData.fullName === 'User')) {
        updates.fullName = callerName;
      }
      if (targetPhone && !callerData.phone) {
        updates.phone = targetPhone;
      }
      if (!callerData.authProvider) {
        updates.authProvider = data.provider;
      }

      if (callerDoc.exists) {
        await callerDocRef.update(updates);
      } else {
        await callerDocRef.set({
          fullName: callerName || 'User',
          phone: targetPhone || '',
          email: callerEmail,
          role: 'passenger',
          rating: 5.0,
          totalRides: 0,
          fcmTokens: [],
          trustedContacts: [],
          authProvider: data.provider,
          photoUrl: callerPhoto,
          linkedProviders: [data.provider],
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      return {
        action: 'KEEP_CURRENT',
        uid: callerUid,
        phoneNumber: targetPhone || callerData.phone || null,
        email: callerEmail || callerData.email || null,
      };
    }

    // CASE B: Existing Account Found at targetUid !== callerUid
    // Verify ownership before restoring session!
    let isOwnershipVerified = false;

    // Proof 1: Trusted Device Token Match
    if (data.deviceId && data.deviceTrustToken) {
      const inputHash = crypto.createHash('sha256').update(data.deviceTrustToken).digest('hex');
      const trustedDeviceDoc = await db
        .collection(APP_CONSTANTS.COLLECTIONS.USERS)
        .doc(targetUid)
        .collection('trustedDevices')
        .doc(data.deviceId)
        .get();

      if (trustedDeviceDoc.exists) {
        const storedHash = trustedDeviceDoc.data()?.tokenHash;
        if (storedHash && storedHash === inputHash) {
          isOwnershipVerified = true;
          // Refresh lastUsedAt
          await trustedDeviceDoc.ref.update({
            lastUsedAt: FieldValue.serverTimestamp(),
          });
        }
      }
    }

    // Proof 2: Verified Email Match
    if (!isOwnershipVerified && isEmailVerified && callerEmail) {
      const targetEmail = targetUserData?.email;
      if (targetEmail && targetEmail.toLowerCase() === callerEmail.toLowerCase()) {
        isOwnershipVerified = true;
      } else {
        try {
          const targetAuthUser = await auth.getUser(targetUid);
          if (targetAuthUser.email && targetAuthUser.email.toLowerCase() === callerEmail.toLowerCase()) {
            isOwnershipVerified = true;
          }
        } catch (_) {}
      }
    }

    if (!isOwnershipVerified) {
      return {
        action: 'NEEDS_PHONE_VERIFICATION',
        maskedPhone: maskPhoneNumber(targetPhone!),
        hasExistingAccount: true,
        targetUid,
      };
    }

    // Ownership verified! Merge caller social data onto targetUid and restore session.
    // Check if callerUid is an empty shell
    const [riderRidesSnap, driverRidesSnap, callerDriverDoc] = await Promise.all([
      db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).where('riderId', '==', callerUid).limit(1).get(),
      db.collection(APP_CONSTANTS.COLLECTIONS.RIDES).where('driverId', '==', callerUid).limit(1).get(),
      db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(callerUid).get(),
    ]);

    const isEmptyShell =
      riderRidesSnap.empty &&
      driverRidesSnap.empty &&
      (!callerDriverDoc.exists || callerDriverDoc.data()?.isVerified !== true);

    const targetUserRef = db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(targetUid);
    const targetMergeUpdates: Record<string, any> = {
      updatedAt: FieldValue.serverTimestamp(),
      linkedProviders: FieldValue.arrayUnion(data.provider),
    };

    if (callerEmail && !targetUserData?.email) {
      targetMergeUpdates.email = callerEmail;
    }
    if (callerPhoto && !targetUserData?.photoUrl) {
      targetMergeUpdates.photoUrl = callerPhoto;
    }
    if (callerName && (!targetUserData?.fullName || targetUserData.fullName === 'User')) {
      targetMergeUpdates.fullName = callerName;
    }

    await targetUserRef.set(targetMergeUpdates, { merge: true });

    // Also update driver document if target has one
    const targetDriverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(targetUid);
    const targetDriverDoc = await targetDriverRef.get();
    if (targetDriverDoc.exists && callerEmail && !targetDriverDoc.data()?.email) {
      await targetDriverRef.update({
        email: callerEmail,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    // If callerUid is a fresh empty shell, clean it up
    if (isEmptyShell) {
      try {
        await callerDocRef.delete();
      } catch (_) {}
      try {
        await auth.deleteUser(callerUid);
      } catch (e) {
        console.warn(`[resolveSocialSession] Could not delete empty shell auth user ${callerUid}:`, e);
      }

      // If target user lacks email in Firebase Auth, sync it now
      if (callerEmail) {
        try {
          const targetAuthUser = await auth.getUser(targetUid);
          if (!targetAuthUser.email) {
            await auth.updateUser(targetUid, {
              email: callerEmail,
              emailVerified: isEmailVerified,
            });
          }
        } catch (_) {}
      }
    }

    // Mint custom token for targetUid so client can sign straight in
    const customToken = await auth.createCustomToken(targetUid);

    return {
      action: 'RESTORE_SESSION',
      customToken,
      targetUid,
      phoneNumber: targetPhone,
      email: callerEmail || targetUserData?.email || null,
    };
  }
);

