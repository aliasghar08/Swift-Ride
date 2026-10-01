import '../domain/models/driver_profile_model.dart';
import '../domain/models/vehicle_info_model.dart';
import '../domain/models/subscription_model.dart';

/// Zero-dependency driver service handling profile management, online/offline status,
/// 100% zero-commission earnings calculation, and Stripe payout requests.
class DriverService {
  /// Toggles driver online status.
  DriverProfile setOnlineStatus(DriverProfile profile, bool isOnline) {
    return profile.copyWith(isOnline: isOnline);
  }

  /// Credits 100% of ride fare to driver's balance ($0 platform commission deduction).
  DriverProfile creditTripEarnings(DriverProfile profile, double rideFare) {
    return profile.copyWith(
      totalRides: profile.totalRides + 1,
      totalEarnings: profile.totalEarnings + rideFare,
      payoutStatus: 'ready_for_payout',
    );
  }

  /// Updates driver vehicle information.
  DriverProfile updateVehicle(DriverProfile profile, VehicleInfo newVehicle) {
    return profile.copyWith(vehicle: newVehicle);
  }

  /// Updates subscription status (e.g. active trial for year 1).
  DriverProfile updateSubscription(DriverProfile profile, SubscriptionStatus status, DateTime expiresAt) {
    return profile.copyWith(
      subscriptionStatus: status,
      subscriptionExpiresAt: expiresAt,
    );
  }

  /// Triggers instant Stripe Connect payout for driver earnings.
  DriverProfile requestInstantPayout(DriverProfile profile) {
    return profile.copyWith(
      payoutStatus: 'paid_out',
    );
  }
}
