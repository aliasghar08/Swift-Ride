import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';

import { APP_CONSTANTS } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';

const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

interface AddressComponent {
  long_name: string;
  short_name: string;
  types: string[];
}

interface GeocodeResult {
  formatted_address: string;
  geometry?: {
    location_type?: string;
    location?: { lat: number; lng: number };
  };
  types: string[];
  address_components: AddressComponent[];
}

/**
 * Extracts and synthesizes exact property-level address details
 * (such as "House 145", "Plot 145", building name, street, and sector/locality).
 */
function buildPrecisePropertyAddress(results: GeocodeResult[]): { address: string; components: AddressComponent[] } {
  if (!results || results.length === 0) {
    return { address: '', components: [] };
  }

  // 1. Prioritize ROOFTOP and granular premises over broad locality/city entries
  const best = results.find(
    (r) =>
      r.geometry?.location_type === 'ROOFTOP' &&
      r.types.some((t) => ['street_address', 'premise', 'subpremise'].includes(t)),
  ) ||
  results.find((r) => r.types.some((t) => ['premise', 'subpremise', 'street_address'].includes(t))) ||
  results.find((r) => r.types.some((t) => ['establishment', 'point_of_interest'].includes(t))) ||
  results[0];

  const comps = best.address_components || [];
  const getComp = (type: string) => comps.find((c) => c.types.includes(type))?.long_name || '';

  const streetNumber = getComp('street_number');
  const premise = getComp('premise') || getComp('subpremise');
  const poi = getComp('point_of_interest') || getComp('establishment');
  const route = getComp('route');
  const sublocality = getComp('sublocality_level_1') || getComp('sublocality') || getComp('neighborhood');
  const locality = getComp('locality') || getComp('administrative_area_level_2');

  const rawFormatted = (best.formatted_address || '').replace(/,\s*Pakistan$/i, '').trim();

  // 2. Synthesize exact property identifier (House/Plot Number)
  if (streetNumber || premise || poi) {
    let propertyPrefix = poi || premise;
    if (!propertyPrefix && streetNumber) {
      // If purely numeric like "145", prefix with "House" or "Plot"
      propertyPrefix = /^\d+[A-Za-z]?$/.test(streetNumber.trim())
        ? `House ${streetNumber.trim()}`
        : streetNumber.trim();
    }

    if (propertyPrefix && !rawFormatted.toLowerCase().includes(propertyPrefix.toLowerCase())) {
      const parts: string[] = [propertyPrefix];
      if (route && !parts.some((p) => p.toLowerCase().includes(route.toLowerCase()))) {
        parts.push(route);
      }
      if (sublocality && !parts.some((p) => p.toLowerCase().includes(sublocality.toLowerCase()))) {
        parts.push(sublocality);
      }
      if (locality && !parts.some((p) => p.toLowerCase().includes(locality.toLowerCase()))) {
        parts.push(locality);
      }
      return { address: parts.join(', '), components: comps };
    }
  }

  return { address: rawFormatted || best.formatted_address, components: comps };
}

export const reverseGeocode = onCall(
  { region: APP_CONSTANTS.REGION, enforceAppCheck: false, cors: true, secrets: [mapsKey] },
  async (request) => {
    assertHasToken(request);
    const data = request.data ?? {};
    const lat = data.lat ?? data.latitude;
    const lng = data.lng ?? data.longitude;
    const queryAddress = (data.plusCode ?? data.address ?? '').toString().trim();

    if ((lat == null || lng == null) && !queryAddress) {
      throw new HttpsError('invalid-argument', 'latitude/longitude or Plus Code/address required');
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
        const params: Record<string, string> = { key };
        if (queryAddress) {
          params.address = queryAddress;
        } else {
          params.latlng = `${lat},${lng}`;
        }

        const { data: resData } = await axios.get(url, { params });

        if (resData.status === 'OK' && resData.results && resData.results.length > 0) {
          const { address, components } = buildPrecisePropertyAddress(resData.results);
          const resolvedLat = resData.results[0].geometry?.location?.lat ?? Number(lat ?? 0.0);
          const resolvedLng = resData.results[0].geometry?.location?.lng ?? Number(lng ?? 0.0);

          return {
            address: address || resData.results[0].formatted_address,
            formattedAddress: resData.results[0].formatted_address,
            components,
            latitude: resolvedLat,
            longitude: resolvedLng,
          };
        }
      } catch (err) {
        console.warn('[reverseGeocode] Geocoding API request failed, using fallback:', err);
      }
    }

    const fallback = lat != null && lng != null
      ? `Pinned Spot (${Number(lat).toFixed(4)}, ${Number(lng).toFixed(4)})`
      : (queryAddress || 'Pinned Location');

    return {
      address: fallback,
      formattedAddress: fallback,
      components: [],
      latitude: Number(lat ?? 0.0),
      longitude: Number(lng ?? 0.0),
    };
  },
);
