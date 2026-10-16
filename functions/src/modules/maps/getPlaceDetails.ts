import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import { APP_CONSTANTS } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

export const getPlaceDetails = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false, cors: true, secrets: [mapsKey] },
  async (request) => {
    assertHasToken(request);

    const placeId = request.data?.placeId;
    if (typeof placeId !== 'string' || placeId.length === 0) {
      throw new HttpsError('invalid-argument', 'placeId required');
    }

    // Direct resolution for synthetic Plus Code and Pinned coordinate IDs
    if (placeId.startsWith('plus:') || placeId.startsWith('pinned:')) {
      const parts = placeId.split(':');
      if (parts.length >= 2) {
        const [latStr, lngStr] = parts[1].split(',');
        const formattedAddress = parts.slice(2).join(':') || 'Pinned Location';
        const lat = parseFloat(latStr);
        const lng = parseFloat(lngStr);
        if (!isNaN(lat) && !isNaN(lng)) {
          return {
            placeId,
            formattedAddress,
            lat,
            lng,
          };
        }
      }
    }

    const key = mapsKey.value();
    if (!key) {
      throw new HttpsError('failed-precondition', 'Place lookup is not configured.');
    }

    // 1. Try Places API (New) Details first
    try {
      const cleanPlaceId = placeId.replace(/^places\//, '');
      const newUrl = `https://places.googleapis.com/v1/places/${encodeURIComponent(cleanPlaceId)}?fields=id,formattedAddress,location&key=${key}`;
      const { data } = await axios.get(newUrl);

      if (data?.location?.latitude != null && data?.location?.longitude != null) {
        return {
          placeId: cleanPlaceId,
          formattedAddress: data.formattedAddress || '',
          lat: data.location.latitude,
          lng: data.location.longitude,
        };
      }
    } catch (newErr) {
      console.warn('[getPlaceDetails] Places API (New) failed, attempting legacy details fallback:', newErr);
    }

    // 2. Legacy Place Details fallback
    try {
      const { data } = await axios.get('https://maps.googleapis.com/maps/api/place/details/json', {
        params: { place_id: placeId, key },
      });

      const location = data?.result?.geometry?.location;
      if (data?.status !== 'OK' || !location) {
        throw new HttpsError('not-found', 'We could not find that place.');
      }

      return {
        placeId,
        formattedAddress: data.result.formatted_address || '',
        lat: location.lat,
        lng: location.lng,
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error('[getPlaceDetails] Place details lookup failed completely', err);
      throw new HttpsError('internal', 'We could not look up that place right now.');
    }
  },
);
