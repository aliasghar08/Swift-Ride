import { describe, it, expect } from 'vitest';
import {
  APP_CONSTANTS,
  calculateSuggestedFare,
  calculateCancellationFee,
} from '../src/config/constants';

describe('SwiftRide Fare & Commission Business Logic', () => {
  it('correctly calculates suggested fare with PKR 150 base, PKR 45/km, PKR 5/min', () => {
    // 5 km, 10 min -> 150 + (5 * 45 = 225) + (10 * 5 = 50) = 425 -> rounded to 430
    const fare1 = calculateSuggestedFare(5, 10);
    expect(fare1).toBe(430);

    // 0 km, 0 min -> 150
    const fare2 = calculateSuggestedFare(0, 0);
    expect(fare2).toBe(150);

    // 10 km, 20 min -> 150 + 450 + 100 = 700
    const fare3 = calculateSuggestedFare(10, 20);
    expect(fare3).toBe(700);
  });

  it('rounds suggested fare to the nearest 10 PKR increment', () => {
    // 3.3 km, 7 min -> 150 + 148.5 + 35 = 333.5 -> rounds to 330
    const fare = calculateSuggestedFare(3.3, 7);
    expect(fare).toBe(330);
  });

  it('verifies 0% commission rate during first year', () => {
    expect(APP_CONSTANTS.COMMISSION_RATE_YEAR_ONE).toBe(0.0);
    const fare = 500.0;
    const platformCommission = fare * APP_CONSTANTS.COMMISSION_RATE_YEAR_ONE;
    expect(platformCommission).toBe(0.0);
  });

  it('enforces cancellation fee tiers in PKR', () => {
    // Before driver accepts: free (0)
    expect(calculateCancellationFee('REQUESTED')).toBe(0.0);

    // After accept, before arrival: PKR 100 fee
    expect(calculateCancellationFee('ACCEPTED')).toBe(100.00);

    // After driver arrives or in progress: PKR 200 fee
    expect(calculateCancellationFee('DRIVER_ARRIVED')).toBe(200.00);
    expect(calculateCancellationFee('IN_PROGRESS')).toBe(200.00);
  });
});
