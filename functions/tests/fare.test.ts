import { describe, it, expect } from 'vitest';
import {
  APP_CONSTANTS,
  calculateSuggestedFare,
  calculateCancellationFee,
} from '../src/config/constants';

describe('SwiftRide Fare & Commission Business Logic', () => {
  it('correctly calculates suggested fare with $2.00 base, $0.50/km, $0.10/min', () => {
    // 5 km, 10 min -> 2.00 + (5 * 0.50 = 2.50) + (10 * 0.10 = 1.00) = 5.50
    const fare1 = calculateSuggestedFare(5, 10);
    expect(fare1).toBe(5.50);

    // 0 km, 0 min -> 2.00
    const fare2 = calculateSuggestedFare(0, 0);
    expect(fare2).toBe(2.00);

    // 10 km, 20 min -> 2.00 + 5.00 + 2.00 = 9.00
    const fare3 = calculateSuggestedFare(10, 20);
    expect(fare3).toBe(9.00);
  });

  it('rounds suggested fare to the nearest 0.50 increment', () => {
    // 3.3 km, 7 min -> 2.00 + 1.65 + 0.70 = 4.35 -> rounds to 4.50
    const fare = calculateSuggestedFare(3.3, 7);
    expect(fare).toBe(4.50);
  });

  it('verifies 0% commission rate during first year', () => {
    expect(APP_CONSTANTS.COMMISSION_RATE_YEAR_ONE).toBe(0.0);
    const fare = 25.0;
    const platformCommission = fare * APP_CONSTANTS.COMMISSION_RATE_YEAR_ONE;
    expect(platformCommission).toBe(0.0);
  });

  it('enforces cancellation fee tiers', () => {
    // Before driver accepts: free ($0)
    expect(calculateCancellationFee('REQUESTED')).toBe(0.0);

    // After accept, before arrival: $2 fee
    expect(calculateCancellationFee('ACCEPTED')).toBe(2.00);

    // After driver arrives or in progress: $5 fee
    expect(calculateCancellationFee('DRIVER_ARRIVED')).toBe(5.00);
    expect(calculateCancellationFee('IN_PROGRESS')).toBe(5.00);
  });
});
