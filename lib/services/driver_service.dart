import '../domain/models/driver_profile_model.dart';
import '../domain/models/vehicle_info_model.dart';
import '../domain/models/subscription_model.dart';

/// Zero-dependency driver service handling profile management, online/offline status,
/// 2% commission earnings calculation, and Stripe payout requests.
class DriverService {
  /// Toggles driver online status.
  DriverProfile setOnlineStatus(DriverProfile profile, bool isOnline) {
    return profile.copyWith(isOnline: isOnline);
  }

  /// Credits 98% of ride fare to driver's balance (2% platform commission deduction).
  DriverProfile creditTripEarnings(DriverProfile profile, double rideFare) {
    final netFare = ((rideFare * 0.98) * 100).round() / 100.0;
    return profile.copyWith(
      totalRides: profile.totalRides + 1,
      totalEarnings: profile.totalEarnings + netFare,
      payoutStatus: 'ready_for_payout',
    );
  }

  /// Updates driver vehicle information.
  DriverProfile updateVehicle(DriverProfile profile, VehicleInfo newVehicle) {
    return profile.copyWith(vehicle: newVehicle);
  }

  /// Updates subscription status (e.g. permanent 2% commission model).
  DriverProfile updateSubscription(DriverProfile profile, SubscriptionStatus status, DateTime expiresAt) {
    return profile.copyWith(
      subscriptionStatus: status,
      subscriptionExpiresAt: expiresAt,
    );
  }

  // NOTE: there is deliberately no local requestInstantPayout here. Marking a
  // payout as paid without the backend would report money as sent that never
  // moved. Payouts go through the `requestPayout` Cloud Function, which owns the
  // ledger and the driver's balance.
}
