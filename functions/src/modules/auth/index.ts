import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db, auth } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated, assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const RegisterUserSchema = z.object({
  fullName: z.string().min(2).max(100),
  phone: z.string().min(7).max(25),
  email: z.string().email().optional(),
  role: z.enum(['rider', 'driver']).default('rider'),
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
  role: z.enum(['rider', 'driver', 'admin']),
});

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

    return { success: true, targetUserId: data.targetUserId, role: data.role };
  }
);

export const deleteUserAccount = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const targetUid = caller.uid;

    // 1. Delete Firestore user document
    await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(targetUid).delete();

    // 2. Delete Firebase Auth user record
    try {
      await auth.deleteUser(targetUid);
    } catch (e) {
      console.warn(`[deleteUserAccount] auth.deleteUser warning for ${targetUid}:`, e);
    }

    return { success: true, message: 'Account permanently deleted' };
  }
);

