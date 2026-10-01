import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertRole } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const VerifyDriverSchema = z.object({
  driverId: z.string().min(1),
  approved: z.boolean(),
  notes: z.string().optional(),
});

export const verifyDriver = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const adminUser = await assertRole(request, ['admin']);
    const data = validateInput(VerifyDriverSchema, request.data);

    const driverRef = db.collection(APP_CONSTANTS.COLLECTIONS.DRIVERS).doc(data.driverId);
    const driverDoc = await driverRef.get();

    if (!driverDoc.exists) {
      throw new HttpsError('not-found', 'Driver document does not exist.');
    }

    await driverRef.update({
      isVerified: data.approved,
      verificationNotes: data.notes || '',
      verifiedBy: adminUser.uid,
      verifiedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      driverId: data.driverId,
      isVerified: data.approved,
    };
  }
);

const GetAdminRidesSchema = z.object({
  status: z.string().optional(),
  limit: z.number().min(1).max(100).default(50),
});

export const getAdminRides = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    await assertRole(request, ['admin']);
    const data = validateInput(GetAdminRidesSchema, request.data);

    let query: FirebaseFirestore.Query = db.collection(APP_CONSTANTS.COLLECTIONS.RIDES);

    if (data.status && data.status !== 'ALL') {
      query = query.where('status', '==', data.status);
    }

    const limitNum = data.limit ?? 50;
    const snapshot = await query.orderBy('createdAt', 'desc').limit(limitNum).get();

    const rides = snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    return { success: true, count: rides.length, rides };
  }
);
