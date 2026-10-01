import 'package:flutter/foundation.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/subscription_model.dart';
import '../domain/models/vehicle_info_model.dart';
import '../services/driver_service.dart';

/// Zero-dependency Driver Provider managing driver state, online availability,
/// and earnings from rides (with 100% zero-commission pass-through).
class DriverProvider extends ChangeNotifier {
  final DriverService _driverService;
  DriverProfile _driverProfile;

  DriverProvider({
    DriverService? driverService,
    DriverProfile? initialProfile,
  })  : _driverService = driverService ?? DriverService(),
        _driverProfile = initialProfile ??
            DriverProfile(
              userId: 'driver_marcus_202',
              licenseNumber: 'DL-83920194A',
              vehicle: const VehicleInfo(
                make: 'Toyota',
                model: 'Camry Hybrid',
                year: 2023,
                plate: '7XYZ890',
                color: 'Midnight Black',
              ),
              isVerified: true,
              isOnline: true,
              subscriptionStatus: SubscriptionStatus.trial,
              subscriptionExpiresAt: DateTime.now().add(const Duration(days: 280)),
              rating: 4.92,
              totalRides: 318,
              totalEarnings: 4250.00,
              createdAt: DateTime.now().subtract(const Duration(days: 120)),
            );

  DriverProfile get driverProfile => _driverProfile;
  DriverProfile get driver => _driverProfile;
  bool get isOnline => _driverProfile.isOnline;
  double get totalEarnings => _driverProfile.totalEarnings;
  int get totalRides => _driverProfile.totalRides;

  void toggleOnline(bool online) {
    _driverProfile = _driverService.setOnlineStatus(_driverProfile, online);
    notifyListeners();
  }

  void creditTripEarnings(double fare) {
    _driverProfile = _driverService.creditTripEarnings(_driverProfile, fare);
    notifyListeners();
  }

  void requestInstantPayout() {
    _driverProfile = _driverService.requestInstantPayout(_driverProfile);
    notifyListeners();
  }

  void updateProfile(DriverProfile profile) {
    _driverProfile = profile;
    notifyListeners();
  }
}
