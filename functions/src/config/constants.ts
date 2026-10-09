export const APP_CONSTANTS = {
  REGION: 'us-central1' as const,
  // Fare formula (PKR): base (150) + (km * 45) + (min * 5)
  FARE_BASE: 150.00,
  FARE_PER_KM: 45.00,
  FARE_PER_MIN: 5.00,
  COMMISSION_RATE_YEAR_ONE: 0.0, // Free 0% commission for first year
  COMMISSION_RATE_YEAR_TWO: 0.13,

  // Cancellation fees (PKR)
  CANCELLATION_FEE_BEFORE_ACCEPT: 0.0,
  CANCELLATION_FEE_AFTER_ACCEPT: 100.00,
  CANCELLATION_FEE_AFTER_ARRIVE: 200.00,

  // Driver Subscriptions (Year 2+) (PKR)
  SUBSCRIPTION_DAILY: 150.00,
  SUBSCRIPTION_MONTHLY: 3500.00,
  SUBSCRIPTION_YEARLY: 35000.00,
  SUBSCRIPTION_GRACE_DAYS: 3,

  // Matching params
  MATCHING_INITIAL_RADIUS_KM: 5.0,
  MATCHING_EXTENDED_RADIUS_KM: 10.0,
  MATCHING_TIMEOUT_SECONDS: 30,
  MAX_BROADCAST_DRIVERS: 20,

  // Geohash settings
  GEOHASH_PRECISION_SEARCH: 5,
  GEOHASH_PRECISION_CELL: 7,

  // Collections
  COLLECTIONS: {
    USERS: 'users',
    DRIVERS: 'drivers',
    RIDES: 'rides',
    RIDE_OFFERS: 'ride_offers',
    PAYMENTS: 'payments',
    PAYOUTS: 'payouts',
    SAFETY_EVENTS: 'safety_events',
    SHARED_TRIPS: 'shared_trips',
    AI_CONVERSATIONS: 'ai_conversations',
    AI_INSIGHTS: 'ai_insights',
    AI_PREFERENCES: 'ai_preferences',
  },

  // RTDB Nodes
  RTDB_NODES: {
    DRIVER_LOCATIONS: 'driver_locations',
    RIDE_TRACKING: 'ride_tracking',
  },
};

export const VEHICLE_ECONOMICS = {
  CAR: {
    fuelRatePerKmPkr: 22.0,        // ~14 km/l at PKR 300/l
    maintenanceRatePerKmPkr: 4.0,  // tyres, oil, wear
  },
} as const;

export type VehicleType = keyof typeof VEHICLE_ECONOMICS;

/**
 * Calculates suggested fare in PKR rounded to the nearest 10.
 */
export function calculateSuggestedFare(distanceKm: number, durationMin: number): number {
  const rawFare =
    APP_CONSTANTS.FARE_BASE +
    distanceKm * APP_CONSTANTS.FARE_PER_KM +
    durationMin * APP_CONSTANTS.FARE_PER_MIN;
  // Round to nearest 10 PKR
  return Math.round(rawFare / 10) * 10;
}

/**
 * Computes cancellation fee based on current ride status.
 */
export function calculateCancellationFee(status: string): number {
  if (status === 'REQUESTED') {
    return APP_CONSTANTS.CANCELLATION_FEE_BEFORE_ACCEPT;
  }
  if (status === 'ACCEPTED') {
    return APP_CONSTANTS.CANCELLATION_FEE_AFTER_ACCEPT;
  }
  if (status === 'DRIVER_ARRIVED' || status === 'IN_PROGRESS') {
    return APP_CONSTANTS.CANCELLATION_FEE_AFTER_ARRIVE;
  }
  return 0.0;
}
