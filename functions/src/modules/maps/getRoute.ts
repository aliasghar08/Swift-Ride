import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { APP_CONSTANTS, VEHICLE_ECONOMICS, VehicleType } from '../../config/constants';
import { assertHasToken } from '../../middleware/auth';
import { validateInput, LatLngSchema } from '../../middleware/validation';
import { z } from 'zod';

/**
 * Server-side Google Maps key.
 */
const mapsKey = defineSecret('GOOGLE_MAPS_SERVER_KEY');

const GetRouteSchema = z.object({
  origin: LatLngSchema,
  destination: LatLngSchema,
  vehicleType: z.string().optional().default('CAR'),
  commissionRate: z.number().optional().default(APP_CONSTANTS.COMMISSION_RATE_YEAR_ONE),
});

export const getRoute = onCall(
  {
    region: APP_CONSTANTS.REGION,
    memory: '512MiB',
    timeoutSeconds: 60,
    enforceAppCheck: false,
    cors: true,
    secrets: [mapsKey],
  },
  async (request) => {
    assertHasToken(request);
    const data = validateInput(GetRouteSchema, request.data);

    const vehicleType = (data.vehicleType || 'CAR') as VehicleType;
    if (!(vehicleType in VEHICLE_ECONOMICS)) {
      throw new HttpsError('invalid-argument', `Invalid vehicleType: ${vehicleType}`);
    }

    const economicsConfig = VEHICLE_ECONOMICS[vehicleType];
    const commissionRate =
      typeof data.commissionRate === 'number'
        ? data.commissionRate
        : APP_CONSTANTS.COMMISSION_RATE_YEAR_ONE;

    const apiKey = mapsKey.value();
    if (!apiKey) {
      console.warn('Routes API key not available');
      return { routes: [], defaultRouteIndex: 0 };
    }

    try {
      const response = await fetch(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
        {
          method: 'POST',
          headers: {
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask':
              'routes.travelAdvisory.tollInfo,' +
              'routes.description,' +
              'routes.duration,' +
              'routes.staticDuration,' +
              'routes.distanceMeters,' +
              'routes.polyline.encodedPolyline,' +
              'routes.legs.travelAdvisory.speedReadingIntervals,' +
              'routes.legs.steps.navigationInstruction,' +
              'routes.legs.steps.distanceMeters,' +
              'routes.legs.steps.staticDuration,' +
              'routes.legs.steps.localizedValues,' +
              'routes.legs.steps.startLocation,' +
              'routes.legs.steps.endLocation,' +
              'routes.legs.steps.polyline.encodedPolyline',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            origin: {
              location: {
                latLng: {
                  latitude: data.origin.latitude,
                  longitude: data.origin.longitude,
                },
              },
            },
            destination: {
              location: {
                latLng: {
                  latitude: data.destination.latitude,
                  longitude: data.destination.longitude,
                },
              },
            },
            travelMode: 'DRIVE',
            routingPreference: 'TRAFFIC_AWARE_OPTIMAL',
            computeAlternativeRoutes: true,
          }),
        }
      );

      if (!response.ok) {
        console.warn('Routes API returned', response.status, await response.text());
        return { routes: [], defaultRouteIndex: 0 };
      }

      const json = await response.json();
      const rawRoutes = json.routes;
      if (!Array.isArray(rawRoutes) || rawRoutes.length === 0) {
        return { routes: [], defaultRouteIndex: 0 };
      }

      interface ProcessedStep {
        distanceKm: number;
        distanceMeters: number;
        distanceText: string;
        durationMin: number;
        durationText: string;
        maneuver: string;
        instruction: string;
        primaryInstruction: string;
        secondaryInstruction?: string;
        roadName?: string;
        startLocation?: { latitude: number; longitude: number };
        endLocation?: { latitude: number; longitude: number };
        encodedPolyline?: string;
        isToll?: boolean;
      }

      interface ProcessedRoute {
        id: string;
        distanceKm: number;
        durationMin: number;
        staticDurationMin: number;
        encodedPolyline: string;
        summary: string;
        trafficLevel: string;
        trafficIntervals: Array<{
          startIndex: number;
          endIndex: number | null;
          speed: string;
        }>;
        steps: ProcessedStep[];
        economics: {
          fuelCost: number;
          maintenanceCost: number;
          tollCost: number;
          driverCost: number;
          riderFare: number;
          commission: number;
          driverProfit: number;
          profitPerMin: number;
        };
        labels: string[];
      }

      const processedRoutes: ProcessedRoute[] = [];

      for (let i = 0; i < rawRoutes.length; i++) {
        const route = rawRoutes[i];
        const encodedPolyline = route.polyline?.encodedPolyline || '';
        if (!encodedPolyline) continue;

        const distanceKm =
          Math.round(((route.distanceMeters || 0) / 1000) * 10) / 10;
        const durationSec = parseInt(
          route.duration?.replace('s', '') || '0',
          10
        );
        const staticDurationSec = parseInt(
          route.staticDuration?.replace('s', '') || '0',
          10
        );

        const durationMin = Math.max(1, Math.round(durationSec / 60));
        const staticDurationMin = staticDurationSec > 0
          ? Math.max(1, Math.round(staticDurationSec / 60))
          : durationMin;

        // Extract toll cost in PKR from travelAdvisory.tollInfo
        let tollCost = 0.0;
        const estimatedPrices = route.travelAdvisory?.tollInfo?.estimatedPrice;
        if (Array.isArray(estimatedPrices)) {
          for (const price of estimatedPrices) {
            const units = Number(price.units || 0);
            const nanos = Number(price.nanos || 0);
            tollCost += units + nanos / 1e9;
          }
        }
        tollCost = Math.round(tollCost * 10) / 10;

        // Economics calculations
        const fuelCost =
          Math.round(distanceKm * economicsConfig.fuelRatePerKmPkr * 10) / 10;
        const maintenanceCost =
          Math.round(distanceKm * economicsConfig.maintenanceRatePerKmPkr * 10) / 10;
        const driverCost =
          Math.round((fuelCost + maintenanceCost + tollCost) * 10) / 10;
        const riderFare =
          Math.round((150 + distanceKm * 45 + durationMin * 5) * 10) / 10;
        const commission =
          Math.round(riderFare * commissionRate * 10) / 10;
        const driverProfit =
          Math.round((riderFare - driverCost - commission) * 10) / 10;
        const profitPerMin =
          Math.round((driverProfit / Math.max(durationMin, 1)) * 10) / 10;

        // Traffic intervals from legs or route advisory
        const rawIntervals =
          route.legs?.[0]?.travelAdvisory?.speedReadingIntervals ||
          route.travelAdvisory?.speedReadingIntervals ||
          [];
        const intervals = rawIntervals.map((interval: any) => ({
          startIndex: interval.startPolylinePointIndex ?? 0,
          endIndex: interval.endPolylinePointIndex ?? null,
          speed: interval.speed || 'NORMAL',
        }));

        const trafficLevel = intervals.some((interval: any) => interval.speed === 'TRAFFIC_JAM')
          ? 'HEAVY'
          : intervals.some((interval: any) => interval.speed === 'SLOW')
            ? 'MODERATE'
            : 'NORMAL';

        // Extract navigation steps from legs with complete Google Maps fidelity
        const steps: ProcessedStep[] = [];
        const rawLegs = Array.isArray(route.legs) ? route.legs : [];
        for (const leg of rawLegs) {
          const rawSteps = Array.isArray(leg.steps) ? leg.steps : [];
          for (const s of rawSteps) {
            const stepDistMeters = Number(s.distanceMeters || 0);
            const stepDistKm = Math.round((stepDistMeters / 1000) * 100) / 100;
            const stepDurationSec = parseInt(
              s.staticDuration?.replace('s', '') || '0',
              10
            );
            const stepDurationMin = Math.round((stepDurationSec / 60) * 10) / 10;

            const nav = s.navigationInstruction;
            const maneuver =
              nav?.maneuver && typeof nav.maneuver === 'string'
                ? nav.maneuver
                : 'STRAIGHT';
            const rawInstruction =
              nav?.instructions && typeof nav.instructions === 'string'
                ? nav.instructions
                : nav?.instruction && typeof nav.instruction === 'string'
                  ? nav.instruction
                  : 'Continue';

            const lines = rawInstruction
              .split('\n')
              .map((l: string) => l.trim())
              .filter((l: string) => l.length > 0);
            const primaryInstruction = lines.length > 0 ? lines[0] : rawInstruction;
            const secondaryInstruction = lines.length > 1 ? lines.slice(1).join(' · ') : undefined;

            // Extract road name if pattern matches "onto <road>"
            let roadName: string | undefined;
            const ontoMatch = primaryInstruction.match(/onto\s+([^,]+)/i);
            if (ontoMatch && ontoMatch[1]) {
              roadName = ontoMatch[1].trim();
            }

            const distanceText =
              s.localizedValues?.distance?.text ||
              (stepDistKm >= 1 ? `${stepDistKm.toFixed(1)} km` : `${stepDistMeters} m`);
            const durationText =
              s.localizedValues?.staticDuration?.text ||
              (stepDurationMin >= 60
                ? `${Math.floor(stepDurationMin / 60)} hr ${Math.round(stepDurationMin % 60)} min`
                : `${Math.max(1, Math.round(stepDurationMin))} min`);

            const startLocation = s.startLocation?.latLng
              ? { latitude: s.startLocation.latLng.latitude, longitude: s.startLocation.latLng.longitude }
              : undefined;
            const endLocation = s.endLocation?.latLng
              ? { latitude: s.endLocation.latLng.latitude, longitude: s.endLocation.latLng.longitude }
              : undefined;
            const stepPolyline = s.polyline?.encodedPolyline || undefined;
            const isToll = rawInstruction.toLowerCase().includes('toll');

            steps.push({
              distanceKm: stepDistKm,
              distanceMeters: stepDistMeters,
              distanceText,
              durationMin: stepDurationMin,
              durationText,
              maneuver,
              instruction: rawInstruction,
              primaryInstruction,
              secondaryInstruction,
              roadName,
              startLocation,
              endLocation,
              encodedPolyline: stepPolyline,
              isToll,
            });
          }
        }

        processedRoutes.push({
          id: `route_${i}`,
          distanceKm,
          durationMin,
          staticDurationMin,
          encodedPolyline,
          summary: route.description || '',
          trafficLevel,
          trafficIntervals: intervals,
          steps,
          economics: {
            fuelCost,
            maintenanceCost,
            tollCost,
            driverCost,
            riderFare,
            commission,
            driverProfit,
            profitPerMin,
          },
          labels: [],
        });
      }

      if (processedRoutes.length === 0) {
        return { routes: [], defaultRouteIndex: 0 };
      }

      // Assign category winner labels:
      // CHEAPEST = argmin(riderFare)
      // FASTEST = argmin(durationMin)
      // BEST_DRIVER = argmax(profitPerMin)
      let minFare = Infinity;
      let minDuration = Infinity;
      let maxProfitPerMin = -Infinity;

      for (const r of processedRoutes) {
        if (r.economics.riderFare < minFare) minFare = r.economics.riderFare;
        if (r.durationMin < minDuration) minDuration = r.durationMin;
        if (r.economics.profitPerMin > maxProfitPerMin) maxProfitPerMin = r.economics.profitPerMin;
      }

      for (const r of processedRoutes) {
        const labels: string[] = [];
        if (r.economics.riderFare === minFare) labels.push('CHEAPEST');
        if (r.durationMin === minDuration) labels.push('FASTEST');
        if (r.economics.profitPerMin === maxProfitPerMin) labels.push('BEST_DRIVER');
        r.labels = labels;
      }

      // Sort: CHEAPEST first, then FASTEST, then BEST_DRIVER, dedup keeping the first occurrence.
      const cheapestRoutes = processedRoutes.filter((r) => r.labels.includes('CHEAPEST'));
      const fastestRoutes = processedRoutes.filter((r) => r.labels.includes('FASTEST'));
      const bestDriverRoutes = processedRoutes.filter((r) => r.labels.includes('BEST_DRIVER'));

      const candidates = [
        ...cheapestRoutes,
        ...fastestRoutes,
        ...bestDriverRoutes,
        ...processedRoutes,
      ];

      const seenIds = new Set<string>();
      const sortedRoutes: ProcessedRoute[] = [];
      for (const r of candidates) {
        if (!seenIds.has(r.id)) {
          seenIds.add(r.id);
          sortedRoutes.push(r);
        }
      }

      // defaultRouteIndex points to FASTEST's position after sort
      let defaultRouteIndex = sortedRoutes.findIndex((r) => r.labels.includes('FASTEST'));
      if (defaultRouteIndex === -1) {
        defaultRouteIndex = 0;
      }

      return {
        routes: sortedRoutes,
        defaultRouteIndex,
      };
    } catch (err) {
      console.warn('Routes API call failed:', err);
      return { routes: [], defaultRouteIndex: 0 };
    }
  }
);
