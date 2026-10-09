import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';

import { APP_CONSTANTS } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

export const reverseGeocode = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false, cors: true, secrets: [mapsKey] },
  async (request) => {
    assertHasToken(request);
    const data = request.data ?? {};
    const lat = data.lat ?? data.latitude;
    const lng = data.lng ?? data.longitude;

    if (lat == null || lng == null) {
      throw new HttpsError('invalid-argument', 'latitude/lat and longitude/lng required');
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
        const { data: resData } = await axios.get(url, {
          params: { latlng: `${lat},${lng}`, key },
        });

        if (resData.status === 'OK' && resData.results && resData.results.length > 0) {
          const formatted = resData.results[0].formatted_address;
          return {
            address: formatted,
            formattedAddress: formatted,
            components: resData.results[0].address_components,
            latitude: Number(lat),
            longitude: Number(lng),
          };
        }
      } catch (err) {
        console.warn('[reverseGeocode] Geocoding API request failed, using fallback:', err);
      }
    }

    const fallback = `Pinned Spot (${Number(lat).toFixed(4)}, ${Number(lng).toFixed(4)})`;
    return {
      address: fallback,
      formattedAddress: fallback,
      components: [],
      latitude: Number(lat),
      longitude: Number(lng),
    };
  },
);
