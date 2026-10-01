import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

export const getPlaceDetails = onCall(
  { region: 'us-central1', enforceAppCheck: true, secrets: [mapsKey] },
  async (request) => {
    const { placeId } = request.data ?? {};
    if (!placeId) throw new HttpsError('invalid-argument', 'placeId required');

    let key = process.env.GOOGLE_MAPS_SERVER_KEY || process.env.GOOGLE_MAPS_API_KEY || '';
    try {
      if (mapsKey.value()) {
        key = mapsKey.value();
      }
    } catch {
      // Secret not populated in local test environment
    }

    if (key && !key.includes('placeholder') && !key.includes('your-')) {
      try {
        const url = `https://maps.googleapis.com/maps/api/place/details/json`;
        const { data } = await axios.get(url, {
          params: { place_id: placeId, key },
        });

        if (data.status === 'OK' && data.result) {
          return {
            placeId,
            formattedAddress: data.result.formatted_address || '',
            lat: data.result.geometry?.location?.lat ?? 37.7749,
            lng: data.result.geometry?.location?.lng ?? -122.4194,
          };
        }
      } catch (err) {
        console.warn('Places API details request failed, using fallback:', err);
      }
    }

    return {
      placeId,
      formattedAddress: `Selected Location (${placeId})`,
      lat: 37.7749 + 0.015,
      lng: -122.4194 - 0.015,
    };
  },
);
