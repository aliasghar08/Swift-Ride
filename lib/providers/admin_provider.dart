import 'package:flutter/foundation.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/subscription_model.dart';
import '../domain/models/vehicle_info_model.dart';
import '../domain/models/ride_model.dart';
import '../services/admin_service.dart';

/// Zero-dependency Admin Provider managing driver approval queues,
/// operational reviews, and system-wide KPI calculations.
class AdminProvider extends ChangeNotifier {
  final AdminService _adminService;
  List<DriverProfile> _pendingDrivers = [];

  AdminProvider({
    AdminService? adminService,
    List<DriverProfile>? initialPendingDrivers,
  })  : _adminService = adminService ?? AdminService(),
        _pendingDrivers = initialPendingDrivers ??
            [
              DriverProfile(
                userId: 'driver_sarah_303',
                licenseNumber: 'DL-99482103B',
                vehicle: const VehicleInfo(
                  make: 'Honda',
                  model: 'Accord EX',
                  year: 2022,
                  plate: '5KMN219',
                  color: 'Pearl White',
                ),
                isVerified: false,
                isOnline: false,
                subscriptionStatus: SubscriptionStatus.trial,
                subscriptionExpiresAt: DateTime.now().add(const Duration(days: 365)),
                rating: 5.0,
                totalRides: 0,
                totalEarnings: 0.0,
                createdAt: DateTime.now().subtract(const Duration(days: 1)),
              ),
            ];

  List<DriverProfile> get pendingDrivers => List.unmodifiable(_pendingDrivers);

  /// Approves or rejects a driver's background check / vehicle registration.
  void verifyDriver(String driverId, bool approved) {
    _pendingDrivers = _pendingDrivers.where((d) => d.userId != driverId).toList();
    notifyListeners();
  }

  /// Calculates real-time platform KPIs based on current ride status and driver pool.
  PlatformKpis getKpis({
    required List<RideModel> rideHistory,
    required RideModel? currentRide,
    required List<DriverProfile> allDrivers,
  }) {
    return _adminService.computePlatformKpis(
      rideHistory: rideHistory,
      currentRide: currentRide,
      allDrivers: allDrivers,
      pendingDrivers: _pendingDrivers,
    );
  }
}
