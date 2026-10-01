class AppConstants {
  static const String appName = 'SwiftRide';
  static const String appTagline = 'Zero Commission Ride-Hailing Platform';

  // Pricing constants (Year 1: 0% Commission)
  static const double baseFare = 2.00;
  static const double perKmFare = 0.50;
  static const double perMinFare = 0.10;
  static const double commissionRateYear1 = 0.00; // Free Year 1!
  static const double standardIndustryCommission = 0.13; // ~13% inDrive comparison

  // Cancellation Fees
  static const double cancelBeforeAccept = 0.00;
  static const double cancelAfterAccept = 2.00;
  static const double cancelAfterArrive = 5.00;

  // Subscriptions (Year 2+)
  static const double subscriptionDaily = 1.00;
  static const double subscriptionMonthly = 15.00;
  static const double subscriptionYearly = 150.00;

  // Default coordinate center (Downtown Hub for simulation)
  static const double defaultLat = 37.7749;
  static const double defaultLng = -122.4194;
}
