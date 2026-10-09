import { CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { db } from '../config/firebase';
import { APP_CONSTANTS } from '../config/constants';

export interface AuthenticatedUser {
  uid: string;
  role: 'rider' | 'driver' | 'admin';
  phone?: string;
  email?: string;
}

export function assertHasToken(request: CallableRequest): { uid: string } {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to perform this operation.');
  }
  return { uid: request.auth.uid };
}

export async function assertAuthenticated(request: CallableRequest): Promise<AuthenticatedUser> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to perform this operation.');
  }

  const uid = request.auth.uid;
  const userDoc = await db.collection(APP_CONSTANTS.COLLECTIONS.USERS).doc(uid).get();

  if (!userDoc.exists) {
    // Return minimal user if document creation is currently pending
    return { uid, role: 'rider' };
  }

  const data = userDoc.data() || {};
  return {
    uid,
    role: data.role || 'rider',
    phone: data.phone,
    email: data.email,
  };
}

export async function assertRole(
  request: CallableRequest,
  allowedRoles: Array<'rider' | 'driver' | 'admin'>
): Promise<AuthenticatedUser> {
  const user = await assertAuthenticated(request);
  if (!allowedRoles.includes(user.role)) {
    throw new HttpsError(
      'permission-denied',
      `Operation restricted. User role '${user.role}' is not permitted.`
    );
  }
  return user;
}
