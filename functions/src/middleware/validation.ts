import { HttpsError } from 'firebase-functions/v2/https';
import { z, ZodSchema } from 'zod';

export function validateInput<T>(schema: ZodSchema<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    const errorDetails = result.error.errors.map((e) => `${e.path.join('.')}: ${e.message}`).join(', ');
    throw new HttpsError('invalid-argument', `Invalid request parameters: ${errorDetails}`);
  }
  return result.data;
}

export const LatLngSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
});

export const GeoLocationSchema = z.object({
  geopoint: LatLngSchema,
  address: z.string().min(1).max(250),
  geohash: z.string().min(1).max(12),
});
