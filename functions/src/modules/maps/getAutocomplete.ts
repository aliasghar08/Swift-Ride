import { onCall } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput, LatLngSchema } from '../../middleware/validation';
import { z } from 'zod';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

const AutocompleteSchema = z.object({
  query: z.string().min(1).max(100),
  location: LatLngSchema.optional(),
  sessionToken: z.string().min(8).max(64).optional(),
});

export const getAutocomplete = onCall(
  { region: APP_CONSTANTS.REGION, secrets: [mapsKey] },
  async (request) => {
    await assertAuthenticated(request);
    const data = validateInput(AutocompleteSchema, request.data);

    const apiKey = mapsKey.value();
    if (!apiKey) {
      return { predictions: [], available: false };
    }

    try {
      const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
      url.searchParams.set('input', data.query);
      url.searchParams.set('key', apiKey);
      
      if (data.location) {
        // --- NEW: Using locationbias instead of strict radius ---
        url.searchParams.set(
          'locationbias',
          `circle:50000@${data.location.latitude},${data.location.longitude}`
        );
      }
      if (data.sessionToken) {
        url.searchParams.set('sessiontoken', data.sessionToken);
      }

      const res = await fetch(url.toString());
      const json = await res.json();

      if (json.status !== 'OK' && json.status !== 'ZERO_RESULTS') {
        console.warn('Places Autocomplete returned', json.status, json.error_message);
        return { predictions: [], available: false };
      }

      return {
        available: true,
        predictions: (json.predictions || []).map((p: any) => ({
          placeId: p.place_id,
          description: p.description,
          mainText: p.structured_formatting?.main_text || p.description,
          secondaryText: p.structured_formatting?.secondary_text || '',
        })),
      };
    } catch (err) {
      console.warn('Places Autocomplete failed', err);
      return { predictions: [], available: false };
    }
  }
);