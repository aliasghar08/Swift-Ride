import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

export const reverseGeocode = onCall(
  { region: 'us-central1', enforceAppCheck: true, secrets: [mapsKey] },
  async (request) => {
    const { lat, lng } = request.data ?? {};
    if (lat == null || lng == null) {
      throw new HttpsError('invalid-argument', 'lat and lng required');
    }

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
        const url = `https://maps.googleapis.com/maps/api/geocode/json`;
        const { data } = await axios.get(url, {
          params: { latlng: `${lat},${lng}`, key },
        });

        if (data.status === 'OK' && data.results && data.results.length > 0) {
          return {
            formattedAddress: data.results[0].formatted_address,
            components: data.results[0].address_components,
            latitude: Number(lat),
            longitude: Number(lng),
          };
        }
      } catch (err) {
        console.warn('Geocoding API request failed, using fallback:', err);
      }
    }

    return {
      formattedAddress: `Pinned Spot (${Number(lat).toFixed(4)}, ${Number(lng).toFixed(4)})`,
      components: [],
      latitude: Number(lat),
      longitude: Number(lng),
    };
  },
);
