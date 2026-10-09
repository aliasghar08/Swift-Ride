import { onCall } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { APP_CONSTANTS } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';
import { validateInput, LatLngSchema } from '../../middleware/validation';
import { z } from 'zod';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

const AutocompleteSchema = z.object({
  query: z.string().min(1).max(100),
  location: LatLngSchema.optional(),
  sessionToken: z.string().min(8).max(64).optional(),
});

export const getAutocomplete = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false, cors: true, secrets: [mapsKey] },
  async (request) => {
    assertHasToken(request);
    const data = validateInput(AutocompleteSchema, request.data);

    const apiKey = mapsKey.value();
    if (!apiKey) {
      console.warn('[getAutocomplete] Google Maps server key is empty');
      return { predictions: [], available: false };
    }

    // 1. Try Places API (New) Autocomplete with Pakistan region filter & GPS bias
    try {
      const newPlacesBody: Record<string, any> = {
        input: data.query,
        includedRegionCodes: ['pk'],
      };

      if (data.location) {
        newPlacesBody.locationBias = {
          circle: {
            center: {
              latitude: data.location.latitude,
              longitude: data.location.longitude,
            },
            radius: 50000.0,
          },
        };
      }

      if (data.sessionToken) {
        newPlacesBody.sessionToken = data.sessionToken;
      }

      const newRes = await fetch('https://places.googleapis.com/v1/places:autocomplete', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
        },
        body: JSON.stringify(newPlacesBody),
      });

      if (newRes.ok) {
        const newJson = await newRes.json();
        const suggestions = newJson.suggestions || [];
        if (suggestions.length > 0) {
          const predictions = suggestions
            .map((s: any) => {
              const p = s.placePrediction;
              if (!p) return null;
              return {
                placeId: p.placeId || (p.place ? p.place.replace(/^places\//, '') : ''),
                description: p.text?.text || '',
                mainText: p.structuredFormat?.mainText?.text || p.text?.text || '',
                secondaryText: p.structuredFormat?.secondaryText?.text || '',
              };
            })
            .filter((p: any) => p && p.placeId);

          return { available: true, predictions };
        }
      } else {
        console.warn('[getAutocomplete] Places API (New) returned status', newRes.status, await newRes.text());
      }
    } catch (newErr) {
      console.warn('[getAutocomplete] Places API (New) failed, attempting legacy fallback:', newErr);
    }

    // 2. Legacy Autocomplete fallback
    try {
      const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
      url.searchParams.set('input', data.query);
      url.searchParams.set('key', apiKey);
      url.searchParams.set('components', 'country:pk');

      if (data.location) {
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
        console.warn('[getAutocomplete] Legacy Places Autocomplete returned', json.status, json.error_message);
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
      console.warn('[getAutocomplete] Places Autocomplete failed completely', err);
      return { predictions: [], available: false };
    }
  }
);