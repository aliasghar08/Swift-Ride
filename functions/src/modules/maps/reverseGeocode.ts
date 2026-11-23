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
 * (such as "Plot 145", "House 145", subpremise, premise/building name, route, and sector/locality).
 */
export function buildPrecisePropertyAddress(results: GeocodeResult[]): {
  address: string;
  components: AddressComponent[];
  extracted: {
    streetNumber: string;
    subpremise: string;
    premise: string;
    route: string;
    sublocality: string;
    locality: string;
  };
} {
  if (!results || results.length === 0) {
    return {
      address: '',
      components: [],
      extracted: {
        streetNumber: '',
        subpremise: '',
        premise: '',
        route: '',
        sublocality: '',
        locality: '',
      },
    };
  }

  // 1. Prioritize ROOFTOP and granular premises over broad locality/city entries
  const best =
    results.find(
      (r) =>
        r.geometry?.location_type === 'ROOFTOP' &&
        r.types.some((t) => ['street_address', 'premise', 'subpremise'].includes(t)),
    ) ||
    results.find((r) => r.types.some((t) => ['premise', 'subpremise', 'street_address'].includes(t))) ||
    results.find((r) => r.types.some((t) => ['establishment', 'point_of_interest', 'route'].includes(t))) ||
    results[0];

  const comps = best.address_components || [];

  // Look up a component type first in `best`, then across secondary results if missing
  const getComp = (type: string): string => {
    const inBest = comps.find((c) => c.types.includes(type))?.long_name;
    if (inBest && inBest.trim().length > 0) return inBest.trim();
    for (const r of results) {
      const found = (r.address_components || []).find((c) => c.types.includes(type))?.long_name;
      if (found && found.trim().length > 0) return found.trim();
    }
    return '';
  };

  const streetNumber = getComp('street_number');
  const subpremise = getComp('subpremise');
  const premise = getComp('premise');
  const poi = getComp('point_of_interest') || getComp('establishment') || getComp('landmark');
  const route = getComp('route');
  const sublocality2 = getComp('sublocality_level_2');
  const sublocality1 =
    getComp('sublocality_level_1') || getComp('sublocality') || getComp('neighborhood');
  const locality = getComp('locality') || getComp('administrative_area_level_2');

  const rawFormatted = (best.formatted_address || '')
    .replace(/,\s*Pakistan$/i, '')
    .replace(/^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,4}\s*,?\s*/i, '')
    .trim();

  // 2. Synthesize granular plot / house / premise / route parts
  const parts: string[] = [];
  const addUniquePart = (part: string) => {
    const clean = part.trim();
    if (!clean) return;
    if (!parts.some((p) => p.toLowerCase().includes(clean.toLowerCase()) || clean.toLowerCase().includes(p.toLowerCase()))) {
      parts.push(clean);
    }
  };

  if (streetNumber) {
    const cleanNum = streetNumber.trim();
    const hasPrefix = /^(plot|house|flat|unit|shop)\b/i.test(cleanNum);
    const formattedNumber = (!hasPrefix && /^\d+\s*[A-Za-z-]?$/i.test(cleanNum))
      ? `Plot ${cleanNum}`
      : cleanNum;
    addUniquePart(formattedNumber);
  }
  if (subpremise) {
    const cleanSub = subpremise.trim();
    const isNum = /^\d+\s*[A-Za-z]?$/i.test(cleanSub);
    addUniquePart(isNum ? `Unit ${cleanSub}` : cleanSub);
  }
  if (premise) {
    addUniquePart(premise);
  }
  if (poi && poi.toLowerCase() !== locality.toLowerCase()) {
    addUniquePart(poi);
  }

  const hasGranularPrefix = parts.length > 0;

  if (route) {
    addUniquePart(route);
  }

  let neighborhood = sublocality1;
  if (sublocality2) {
    if (!neighborhood) {
      neighborhood = sublocality2;
    } else if (!neighborhood.toLowerCase().includes(sublocality2.toLowerCase())) {
      neighborhood = `${neighborhood} ${sublocality2}`;
    }
  }
  if (neighborhood) {
    const cleanNeighborhood = neighborhood
      .replace(/Satellite Town Block A Satellite Town/gi, 'Satellite Town Block A')
      .replace(/Satellite Block A Town/gi, 'Satellite Town Block A');
    addUniquePart(cleanNeighborhood);
  }
  if (locality) {
    addUniquePart(locality);
  }

  const extracted = {
    streetNumber,
    subpremise,
    premise: premise || poi,
    route,
    sublocality: sublocality2 ? `${sublocality2}, ${sublocality1}`.replace(/,\s*$/, '') : sublocality1,
    locality,
  };

  if (hasGranularPrefix && parts.length > 0) {
    return {
      address: parts.join(', '),
      components: comps,
      extracted,
    };
  }

  return {
    address: rawFormatted || parts.join(', ') || best.formatted_address,
    components: comps,
    extracted,
  };
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
        const params: Record<string, string> = { key, extra_computations: 'ADDRESS_DESCRIPTORS' };
        if (queryAddress) {
          params.address = queryAddress;
        } else {
          params.latlng = `${lat},${lng}`;
        }

        const { data: resData } = await axios.get(url, { params });

        if (resData.status === 'OK' && resData.results && resData.results.length > 0) {
          const { address, components, extracted } = buildPrecisePropertyAddress(resData.results);
          const resolvedLat = resData.results[0].geometry?.location?.lat ?? Number(lat ?? 0.0);
          const resolvedLng = resData.results[0].geometry?.location?.lng ?? Number(lng ?? 0.0);

          return {
            address: address || resData.results[0].formatted_address,
            formattedAddress: address || resData.results[0].formatted_address,
            components,
            extracted,
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
