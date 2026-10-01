class AppConstants {
  static const String appName = 'SwiftRide';
  static const String appTagline = 'Zero Commission Ride-Hailing Platform';

  // Pricing constants in PKR (Year 1: 0% Commission)
  static const double baseFare = 150.00; // Base fare PKR 150
  static const double perKmFare = 45.00; // PKR 45 per km
  static const double perMinFare = 5.00; // PKR 5 per min
  static const double commissionRateYear1 = 0.00; // Free Year 1!
  static const double standardIndustryCommission = 0.13; // ~13% inDrive comparison

  // Cancellation Fees in PKR
  static const double cancelBeforeAccept = 0.00;
  static const double cancelAfterAccept = 100.00; // PKR 100
  static const double cancelAfterArrive = 200.00; // PKR 200

  // Subscriptions in PKR (Year 2+)
  static const double subscriptionDaily = 150.00; // PKR 150/day
  static const double subscriptionMonthly = 3500.00; // PKR 3,500/month
  static const double subscriptionYearly = 35000.00; // PKR 35,000/year

  // Default coordinate center (Downtown Hub for simulation)
  static const double defaultLat = 37.7749;
  static const double defaultLng = -122.4194;
}
