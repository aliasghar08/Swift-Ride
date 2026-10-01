import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { db } from '../../config/firebase';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput } from '../../middleware/validation';
import { z } from 'zod';

const GetRideHistorySchema = z.object({
  role: z.enum(['rider', 'driver']).default('rider'),
  limit: z.number().min(1).max(50).default(20),
});

export const getRideHistory = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false },
  async (request) => {
    const caller = await assertAuthenticated(request);
    const data = validateInput(GetRideHistorySchema, request.data);

    const field = data.role === 'rider' ? 'riderId' : 'driverId';
    const limitNum = data.limit ?? 20;
    const snapshot = await db
      .collection(APP_CONSTANTS.COLLECTIONS.RIDES)
      .where(field, '==', caller.uid)
      .orderBy('createdAt', 'desc')
      .limit(limitNum)
      .get();

    const rides = snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    return { success: true, count: rides.length, rides };
  }
);
