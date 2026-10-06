import { onCall } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { APP_CONSTANTS } from '../../config/constants';
import { assertAuthenticated } from '../../middleware/auth';
import { validateInput, LatLngSchema } from '../../middleware/validation';
import { z } from 'zod';

/**
 * Server-side Google Maps key.
 *
 * This MUST be declared as a secret and bound to the function. It previously
 * read `process.env.GOOGLE_MAPS_API_KEY` with no `secrets:` binding, so the
 * variable was always empty in production and the Routes API was never actually
 * called — every rider silently got a synthetic straight-line estimate.
 */
const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

const GetRouteSchema = z.object({
  origin: LatLngSchema,
  destination: LatLngSchema,
});

// Haversine distance helper
function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371; // Earth radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

export const getRoute = onCall(
  {
    region: APP_CONSTANTS.REGION,
    memory: '512MiB',
    timeoutSeconds: 60,
    secrets: [mapsKey],
  },
  async (request) => {
    await assertAuthenticated(request);
    const { origin, destination } = validateInput(GetRouteSchema, request.data);

    const apiKey = mapsKey.value();

    if (apiKey) {
      try {
        const response = await fetch(
          'https://routes.googleapis.com/directions/v2:computeRoutes',
          {
            method: 'POST',
            headers: {
              'X-Goog-Api-Key': apiKey,
              'X-Goog-FieldMask':
                'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,' +
                'routes.travelAdvisory.speedReadingIntervals',
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              origin: {
                location: {
                  latLng: {
                    latitude: origin.latitude,
                    longitude: origin.longitude,
                  },
                },
              },
              destination: {
                location: {
                  latLng: {
                    latitude: destination.latitude,
                    longitude: destination.longitude,
                  },
                },
              },
              travelMode: 'DRIVE',
              routingPreference: 'TRAFFIC_AWARE_OPTIMAL',
            }),
          }
        );

        if (response.ok) {
          const json = await response.json();
          const route = json.routes?.[0];
          if (route) {
            const distanceKm = Math.round(((route.distanceMeters || 0) / 1000) * 10) / 10;
            const durationSec = parseInt(route.duration?.replace('s', '') || '0', 10);
            const encodedPolyline = route.polyline?.encodedPolyline || '';

            // Only report a road route when we actually got road geometry back.
            if (encodedPolyline) {
              // Real per-segment traffic. The UI colours the polyline from these
              // index ranges instead of assuming the whole route is clear.
              const intervals = (route.travelAdvisory?.speedReadingIntervals || []).map(
                (interval: any) => ({
                  startIndex: interval.startPolylinePointIndex ?? 0,
                  endIndex: interval.endPolylinePointIndex ?? null,
                  speed: interval.speed || 'NORMAL',
                })
              );

              return {
                distanceKm,
                durationMin: Math.max(1, Math.round(durationSec / 60)),
                encodedPolyline,
                trafficLevel: intervals.some((i: any) => i.speed === 'TRAFFIC_JAM')
                  ? 'HEAVY'
                  : intervals.some((i: any) => i.speed === 'SLOW')
                    ? 'MODERATE'
                    : 'NORMAL',
                trafficIntervals: intervals,
                isEstimated: false,
              };
            }
          }
        } else {
          console.warn('Routes API returned', response.status, await response.text());
        }
      } catch (err) {
        console.warn('Routes API call failed, falling back to estimate', err);
      }
    }

    // Explicitly-labelled estimate. The polyline is intentionally empty so the
    // client draws a straight line and knows it is not road geometry.
    const directDistKm = haversineDistance(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude
    );
    const distanceKm = Math.max(0.5, Math.round(directDistKm * 1.3 * 10) / 10);
    const durationMin = Math.max(3, Math.round(distanceKm * 2.2));

    return {
      distanceKm,
      durationMin,
      encodedPolyline: '',
      trafficLevel: 'NORMAL',
      // No geometry means no per-segment traffic either. Reporting NORMAL here
      // would falsely imply the road is clear.
      trafficIntervals: [],
      isEstimated: true,
    };
  }
);
