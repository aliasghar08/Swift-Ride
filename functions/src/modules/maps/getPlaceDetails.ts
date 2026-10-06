import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

export const getPlaceDetails = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: true, secrets: [mapsKey] },
  async (request) => {
    // Every sibling maps function authenticates first. Without this, anyone who
    // could reach the endpoint could spend the Places quota anonymously.
    await assertAuthenticated(request);

    const placeId = request.data?.placeId;
    if (typeof placeId !== 'string' || placeId.length === 0) {
      throw new HttpsError('invalid-argument', 'placeId required');
    }

    const key = mapsKey.value();
    if (!key) {
      throw new HttpsError('failed-precondition', 'Place lookup is not configured.');
    }

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
      // Never invent coordinates. The previous fallback returned a point near
      // San Francisco, silently sending riders to the wrong continent.
      console.error('Places details lookup failed', err);
      throw new HttpsError('internal', 'We could not look up that place right now.');
    }
  },
);
