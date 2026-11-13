import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import { APP_CONSTANTS } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';
import { buildPrecisePropertyAddress } from './reverseGeocode';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

function formatNewPlacesDetailAddress(data: any): string {
  const displayName = data?.displayName?.text?.trim() || '';
  const rawFormatted = (data?.formattedAddress || '')
    .replace(/,\s*Pakistan$/i, '')
    .trim();

  const comps: any[] = Array.isArray(data?.addressComponents) ? data.addressComponents : [];
  const getComp = (type: string): string => {
    const found = comps.find((c) => Array.isArray(c.types) && c.types.includes(type));
    return (found?.longText || found?.shortText || '').trim();
  };

  const streetNumber = getComp('street_number');
  const subpremise = getComp('subpremise');
  const premise = getComp('premise');
  const route = getComp('route');
  const sublocality2 = getComp('sublocality_level_2');
  const sublocality1 = getComp('sublocality_level_1') || getComp('sublocality') || getComp('neighborhood');
  const locality = getComp('locality') || getComp('administrative_area_level_2');

  const parts: string[] = [];
  const addUnique = (val: string) => {
    const clean = val.trim();
    if (!clean) return;
    if (!parts.some((p) => p.toLowerCase().includes(clean.toLowerCase()) || clean.toLowerCase().includes(p.toLowerCase()))) {
      parts.push(clean);
    }
  };

  const isPlusCode = /^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,4}$/i.test(displayName);
  if (displayName && !isPlusCode && displayName.toLowerCase() !== locality.toLowerCase()) {
    addUnique(displayName);
  }
  if (streetNumber) {
    addUnique(/^\d+[A-Za-z-]?$/.test(streetNumber) ? `Plot ${streetNumber}` : streetNumber);
  }
  if (subpremise) addUnique(subpremise);
  if (premise) addUnique(premise);
  if (route) addUnique(route);
  if (sublocality2) addUnique(sublocality2);
  if (sublocality1) addUnique(sublocality1);
  if (locality) addUnique(locality);

  if (parts.length > 0 && (streetNumber || subpremise || premise || displayName)) {
    return parts.join(', ');
  }
  return rawFormatted || parts.join(', ');
}

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

    // 1. Try Places API (New) Details first with granular addressComponents
    try {
      const cleanPlaceId = placeId.replace(/^places\//, '');
      const newUrl = `https://places.googleapis.com/v1/places/${encodeURIComponent(cleanPlaceId)}?fields=id,displayName,formattedAddress,addressComponents,location&key=${key}`;
      const { data } = await axios.get(newUrl);

      if (data?.location?.latitude != null && data?.location?.longitude != null) {
        const granularAddress = formatNewPlacesDetailAddress(data);
        return {
          placeId: cleanPlaceId,
          formattedAddress: granularAddress || data.formattedAddress || '',
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
        params: {
          place_id: placeId,
          fields: 'place_id,name,formatted_address,address_components,geometry',
          key,
        },
      });

      const location = data?.result?.geometry?.location;
      if (data?.status !== 'OK' || !location) {
        throw new HttpsError('not-found', 'We could not find that place.');
      }

      const { address } = buildPrecisePropertyAddress([data.result]);
      return {
        placeId,
        formattedAddress: address || data.result.formatted_address || '',
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
