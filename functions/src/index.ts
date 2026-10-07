// SwiftRide Cloud Functions Gen 2 Main Export
// Force redeploy & refresh IAM policies: 2026-10-07

// 1. Auth Module
export { registerUser, verifyOtp, setUserRole } from './modules/auth';

// 2. Rides Module (Lifecycle & inDrive-style negotiation)
export {
  requestRide,
  submitOffer,
  acceptOffer,
  updateRideStatus,
  cancelRide,
  getRideHistory,
} from './modules/rides';

// 3. Drivers Module
export {
  toggleOnline,
  updateDriverLocation,
  getEarnings,
  requestPayout,
  subscribePlan,
} from './modules/drivers';

// 4. Payments Module (Stripe PaymentIntents & Webhooks)
export {
  createPaymentIntent,
  confirmCashPayment,
  getPaymentMethods,
  deletePaymentMethod,
  stripeWebhook,
} from './modules/payments';

// 5. Maps Proxy Module (Routes Preferred, Places Autocomplete, Geocoding)
export { getRoute, getAutocomplete, getPlaceDetails, reverseGeocode } from './modules/maps';

// 6. Safety Module (SOS Emergency, Trip Sharing)
export { triggerSos, resolveSos, shareTrip, getSharedTrip } from './modules/safety';

// 7. Admin Module
export { getDashboardStats, verifyDriver, getAdminRides } from './modules/admin';

// 8. Firestore Reactive Triggers
export {
  onRideCreated,
  onRideUpdated,
  onPaymentCreated,
  onDriverDocUploaded,
} from './triggers';

// 9. Scheduled Jobs (Cloud Scheduler)
export {
  checkDriverSubscriptions,
  generateWeeklyReports,
  cleanupStaleRides,
  persistLocations,
} from './scheduled';

// 10. AI Module (Gemini Developer API + App Check)
export {
  generateEarningsInsight,
  dailyEarningsInsightSchedule,
  safetyCheckIn,
  conversationalAssistant,
  predictVehicleMaintenance,
  weeklyMaintenanceSchedule,
  routeOptimizer,
} from './modules/ai';