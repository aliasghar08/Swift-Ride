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

// Major Pakistani cities with center coordinates
const PAKISTAN_CITIES: Record<string, { lat: number; lng: number }> = {
  'toba tek singh': { lat: 30.9747, lng: 72.4828 },
  jhang: { lat: 31.2681, lng: 72.3181 },
  sargodha: { lat: 32.0836, lng: 72.6711 },
  faisalabad: { lat: 31.4504, lng: 73.1350 },
  lahore: { lat: 31.5497, lng: 74.3436 },
  islamabad: { lat: 33.6844, lng: 73.0479 },
  rawalpindi: { lat: 33.5651, lng: 73.0169 },
  karachi: { lat: 24.8607, lng: 67.0011 },
  multan: { lat: 30.1575, lng: 71.5249 },
  peshawar: { lat: 34.0151, lng: 71.5249 },
  quetta: { lat: 30.1798, lng: 66.9750 },
  gujranwala: { lat: 32.1877, lng: 74.1945 },
  sialkot: { lat: 32.4945, lng: 74.5229 },
  bahawalpur: { lat: 29.3544, lng: 71.6911 },
  sukkur: { lat: 27.7052, lng: 68.8574 },
  hyderabad: { lat: 25.3960, lng: 68.3578 },
  chiniot: { lat: 31.7200, lng: 72.9789 },
  bhakkar: { lat: 31.6253, lng: 71.0657 },
  mianwali: { lat: 32.5839, lng: 71.5370 },
  khushab: { lat: 32.2955, lng: 72.3503 },
  rajanpur: { lat: 29.1035, lng: 70.3250 },
  okara: { lat: 30.8080, lng: 73.4458 },
  sahiwal: { lat: 30.6682, lng: 73.1114 },
  sheikhupura: { lat: 31.7131, lng: 73.9783 },
  kasur: { lat: 31.1179, lng: 74.4461 },
  jhelum: { lat: 32.9405, lng: 73.7276 },
  attock: { lat: 33.7660, lng: 72.3609 },
  chakwal: { lat: 32.9328, lng: 72.8630 },
  mardan: { lat: 34.1989, lng: 72.0404 },
  abbottabad: { lat: 34.1688, lng: 73.2215 },
  murree: { lat: 33.9070, lng: 73.3943 },
  gilgit: { lat: 35.9221, lng: 74.3087 },
  skardu: { lat: 35.2971, lng: 75.6333 },
};

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

    // 1. Detect city name in query (lowercase comparison)
    const lowerQuery = data.query.toLowerCase();
    let targetCenter: { lat: number; lng: number } | null = null;
    let targetRadiusMeters = 50000;

    for (const [cityName, coords] of Object.entries(PAKISTAN_CITIES)) {
      const regex = new RegExp(`\\b${cityName}\\b`, 'i');
      if (regex.test(lowerQuery)) {
        targetCenter = coords;
        targetRadiusMeters = 50000;
        break;
      }
    }

    // 2. If no city name found in query, use rider location with hard restriction
    if (!targetCenter && data.location) {
      targetCenter = {
        lat: data.location.latitude,
        lng: data.location.longitude,
      };
      // Google Places API (New) maximum allowed circle radius is 50,000 meters
      targetRadiusMeters = 50000;
    }

    // 2b. Detect Plus Code in query (e.g. "78G5+48 Jhang, Pakistan", "8J3J78G5+48")
    const plusCodeRegex = /\b([23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,4})\b/i;
    const plusMatch = data.query.match(plusCodeRegex);
    const plusPredictions: any[] = [];

    if (plusMatch) {
      try {
        const geoUrl = new URL('https://maps.googleapis.com/maps/api/geocode/json');
        geoUrl.searchParams.set('address', data.query);
        geoUrl.searchParams.set('key', apiKey);
        geoUrl.searchParams.set('components', 'country:pk');

        const geoRes = await fetch(geoUrl.toString());
        const geoJson = await geoRes.json();
        if (geoJson.status === 'OK' && geoJson.results?.length > 0) {
          const first = geoJson.results[0];
          plusPredictions.push({
            placeId: `plus:${first.geometry.location.lat},${first.geometry.location.lng}:${first.formatted_address}`,
            description: first.formatted_address,
            mainText: `Pinned Location (${plusMatch[1].toUpperCase()})`,
            secondaryText: first.formatted_address,
          });
        }
      } catch (plusErr) {
        console.warn('[getAutocomplete] Geocoding API lookup for Plus Code failed:', plusErr);
      }
    }

    // 3. Try Places API (New) Autocomplete with Pakistan region filter & hard location restriction
    try {
      const newPlacesBody: Record<string, any> = {
        input: data.query,
        includedRegionCodes: ['pk'],
      };

      if (targetCenter) {
        newPlacesBody.locationRestriction = {
          circle: {
            center: {
              latitude: targetCenter.lat,
              longitude: targetCenter.lng,
            },
            radius: Math.min(targetRadiusMeters, 50000.0),
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

          return { available: true, predictions: [...plusPredictions, ...predictions] };
        }
      } else {
        console.warn('[getAutocomplete] Places API (New) returned status', newRes.status, await newRes.text());
      }
    } catch (newErr) {
      console.warn('[getAutocomplete] Places API (New) failed, attempting legacy fallback:', newErr);
    }

    // 4. Legacy Autocomplete fallback
    try {
      const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
      url.searchParams.set('input', data.query);
      url.searchParams.set('key', apiKey);
      url.searchParams.set('components', 'country:pk');

      if (targetCenter) {
        url.searchParams.set(
          'locationrestriction',
          `circle:${targetRadiusMeters}@${targetCenter.lat},${targetCenter.lng}`
        );
      }
      if (data.sessionToken) {
        url.searchParams.set('sessiontoken', data.sessionToken);
      }

      const res = await fetch(url.toString());
      const json = await res.json();

      if (json.status !== 'OK' && json.status !== 'ZERO_RESULTS') {
        console.warn('[getAutocomplete] Legacy Places Autocomplete returned', json.status, json.error_message);
        return { predictions: plusPredictions, available: plusPredictions.length > 0 };
      }

      const legacyPreds = (json.predictions || []).map((p: any) => ({
        placeId: p.place_id,
        description: p.description,
        mainText: p.structured_formatting?.main_text || p.description,
        secondaryText: p.structured_formatting?.secondary_text || '',
      }));

      return {
        available: true,
        predictions: [...plusPredictions, ...legacyPreds],
      };
    } catch (err) {
      console.warn('[getAutocomplete] Places Autocomplete failed completely', err);
      return { predictions: plusPredictions, available: plusPredictions.length > 0 };
    }
  }
);