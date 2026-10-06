import '../core/utils/distance_calculator.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/ride_model.dart';

class PlatformKpis {
  final int totalRides;
  final double grossMarketplaceValue;
  final double driverCommissionSavings;
  final int activeDrivers;
  final int pendingVerifications;

  /// Unresolved emergency alerts across the platform.
  ///
  /// Null when this figure is genuinely unknown (the stats have not loaded, or
  /// the local fallback was used). It is nullable on purpose: reporting 0 would
  /// be a false all-clear on a safety-critical tile, and the dashboard used to
  /// do exactly that by reading a local list that was always empty.
  final int? unresolvedSafetyEvents;

  const PlatformKpis({
    required this.totalRides,
    required this.grossMarketplaceValue,
    required this.driverCommissionSavings,
    required this.activeDrivers,
    required this.pendingVerifications,
    this.unresolvedSafetyEvents,
  });

  /// Builds KPIs from the `getDashboardStats` Cloud Function response.
  ///
  /// These are real platform aggregates. The local
  /// [AdminService.computePlatformKpis] only ever saw the current session's own
  /// ride history, so it reported near-zero activity on a live platform.
  factory PlatformKpis.fromServer(Map<String, dynamic> data) {
    int asInt(String key) => (data[key] as num?)?.toInt() ?? 0;
    double asDouble(String key) => (data[key] as num?)?.toDouble() ?? 0;

    return PlatformKpis(
      totalRides: asInt('totalRides'),
      grossMarketplaceValue: asDouble('grossBookingVolume'),
      driverCommissionSavings: asDouble('zeroCommissionDriverSavings'),
      activeDrivers: asInt('activeOnlineDrivers'),
      pendingVerifications: asInt('pendingDriverVerifications'),
      // Deliberately not `asInt`: an absent field must stay unknown. Defaulting
      // it to 0 would render "No open alerts" — a false all-clear on the safety
      // tile if the backend ever omits the figure.
      unresolvedSafetyEvents: (data['unresolvedSafetyEvents'] as num?)?.toInt(),
    );
  }
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
