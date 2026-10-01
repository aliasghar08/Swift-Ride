import '../core/utils/distance_calculator.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/ride_model.dart';

class PlatformKpis {
  final int totalRides;
  final double grossMarketplaceValue;
  final double driverCommissionSavings;
  final int activeDrivers;
  final int pendingVerifications;

  const PlatformKpis({
    required this.totalRides,
    required this.grossMarketplaceValue,
    required this.driverCommissionSavings,
    required this.activeDrivers,
    required this.pendingVerifications,
  });
}

/// Zero-dependency admin service for KPI metrics aggregation, driver document
/// approvals, and operational health monitoring.
class AdminService {
  /// Computes platform KPIs based on ride history, current active rides, and driver pool.
  PlatformKpis computePlatformKpis({
    required List<RideModel> rideHistory,
    required RideModel? currentRide,
    required List<DriverProfile> allDrivers,
    required List<DriverProfile> pendingDrivers,
  }) {
    final totalRides = rideHistory.length + (currentRide != null ? 1 : 0);
    double gmv = 0.0;

    for (final ride in rideHistory) {
      gmv += ride.acceptedFare ?? ride.offeredFare;
    }
    if (currentRide != null) {
      gmv += currentRide.acceptedFare ?? currentRide.offeredFare;
    }

    final driverSavings = DistanceCalculator.calculateZeroCommissionSavings(gmv);
    final activeDrivers = allDrivers.where((d) => d.isOnline).length;

    return PlatformKpis(
      totalRides: totalRides,
      grossMarketplaceValue: gmv,
      driverCommissionSavings: driverSavings,
      activeDrivers: activeDrivers,
      pendingVerifications: pendingDrivers.length,
    );
  }

  /// Approves a pending driver application.
  DriverProfile approveDriver(DriverProfile driver) {
    return driver.copyWith(isVerified: true);
  }
}
