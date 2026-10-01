import { describe, it, expect } from 'vitest';
import * as geofire from 'geofire-common';

describe('SwiftRide Geospatial Matching Logic', () => {
  it('encodes and computes distance correctly', () => {
    // City center: (37.7749, -122.4194)
    const center: [number, number] = [37.7749, -122.4194];
    const hash = geofire.geohashForLocation(center, 7);
    expect(hash).toBeDefined();
    expect(hash.length).toBe(7);

    // Nearby driver (~1.5 km away)
    const driverLoc: [number, number] = [37.785, -122.406];
    const distKm = geofire.distanceBetween(driverLoc, center);
    expect(distKm).toBeGreaterThan(0.5);
    expect(distKm).toBeLessThan(5.0);
  });

  it('generates query bounds for 5km search radius', () => {
    const center: [number, number] = [37.7749, -122.4194];
    const radiusM = 5000;
    const bounds = geofire.geohashQueryBounds(center, radiusM);

    expect(bounds.length).toBeGreaterThan(0);
    for (const b of bounds) {
      expect(b[0] < b[1]).toBe(true);
    }
  });
});
