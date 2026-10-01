export const APP_CONSTANTS = {
  REGION: 'us-central1' as const,
  // Fare formula: base + (km * 0.50) + (min * 0.10)
  FARE_BASE: 2.00,
  FARE_PER_KM: 0.50,
  FARE_PER_MIN: 0.10,
  COMMISSION_RATE_YEAR_ONE: 0.0, // Free 0% commission for first year

  // Cancellation fees
  CANCELLATION_FEE_BEFORE_ACCEPT: 0.0,
  CANCELLATION_FEE_AFTER_ACCEPT: 2.00,
  CANCELLATION_FEE_AFTER_ARRIVE: 5.00,

  // Driver Subscriptions (Year 2+)
  SUBSCRIPTION_DAILY: 1.00,
  SUBSCRIPTION_MONTHLY: 15.00,
  SUBSCRIPTION_YEARLY: 150.00,
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

/**
 * Calculates suggested fare rounded to the nearest 0.50.
 */
export function calculateSuggestedFare(distanceKm: number, durationMin: number): number {
  const rawFare =
    APP_CONSTANTS.FARE_BASE +
    distanceKm * APP_CONSTANTS.FARE_PER_KM +
    durationMin * APP_CONSTANTS.FARE_PER_MIN;
  // Round to nearest 0.50
  return Math.round(rawFare * 2) / 2;
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
