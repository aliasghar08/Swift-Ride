import 'package:flutter/foundation.dart';
import '../domain/models/driver_profile_model.dart';
import '../services/driver_service.dart';
import '../services/firestore/firestore_driver_service.dart';

/// Zero-dependency Driver Provider managing driver state, online availability,
/// and earnings from rides (with 100% zero-commission pass-through).
class DriverProvider extends ChangeNotifier {
  final DriverService _driverService;
  final FirestoreDriverService _firestoreService;
  DriverProfile _driverProfile;

  DriverProvider({
    DriverService? driverService,
    FirestoreDriverService? firestoreService,
    DriverProfile? initialProfile,
  })  : _driverService = driverService ?? DriverService(),
        _firestoreService = firestoreService ?? FirestoreDriverService(),
        // Starts empty. This used to be seeded with a fabricated driver
        // ("driver_marcus_202", plate 7XYZ890, 318 rides, PKR 4,250 earned), so
        // the cockpit displayed invented earnings a driver could try to withdraw.
        _driverProfile = initialProfile ?? DriverProfile.empty();

  /// Real earnings and payout balance reported by the backend.
  DriverEarnings? _earnings;
  bool _isLoadingProfile = false;
  String? _profileError;

  DriverEarnings? get earnings => _earnings;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get profileError => _profileError;

  /// Authoritative withdrawable balance. Falls back to the locally-known figure
  /// only until the server responds.
  double get availablePayoutBalance =>
      _earnings?.availablePayoutBalance ?? _driverProfile.totalEarnings;

  /// Loads this driver's real profile and earnings.
  ///
  /// Returns false when the profile could not be loaded, so the cockpit can say
  /// so rather than showing an empty dashboard as if it were the truth.
  Future<bool> loadForUser(String userId) async {
    if (userId.isEmpty) return false;

    _isLoadingProfile = true;
    _profileError = null;
    notifyListeners();

    try {
      final loaded = await _firestoreService.getDriverProfile(userId);
      if (loaded != null) {
        _driverProfile = loaded;
      } else {
        // No driver record yet: keep the real identity but claim nothing else.
        _driverProfile = DriverProfile.empty(userId: userId);
      }

      _earnings = await _firestoreService.fetchEarnings();
      return true;
    } catch (e) {
      debugPrint('[DriverProvider] loadForUser failed: $e');
      _profileError = 'We could not load your driver profile. Pull to retry.';
      return false;
    } finally {
      _isLoadingProfile = false;
      notifyListeners();
    }
  }

  DriverProfile get driverProfile => _driverProfile;
  DriverProfile get driver => _driverProfile;
  bool get isOnline => _driverProfile.isOnline;
  double get totalEarnings => _driverProfile.totalEarnings;
  int get totalRides => _driverProfile.totalRides;

  /// Changes availability, server-side.
  ///
  /// Returns null on success, or a message explaining the refusal. Local state
  /// is only updated once the backend confirms, so the switch cannot show
  /// "online" when dispatch still considers the driver unavailable.
  Future<String?> toggleOnline(
    bool online, {
    double? latitude,
    double? longitude,
  }) async {
    final error = await _firestoreService.setOnline(
      isOnline: online,
      latitude: latitude,
      longitude: longitude,
    );

    if (error == null) {
      _driverProfile = _driverService.setOnlineStatus(_driverProfile, online);
      _availabilityError = null;
    } else {
      _availabilityError = error;
    }
    notifyListeners();
    return error;
  }

  String? _availabilityError;
  String? get availabilityError => _availabilityError;

  void creditTripEarnings(double fare) {
    _driverProfile = _driverService.creditTripEarnings(_driverProfile, fare);
    notifyListeners();
  }

  // Payouts are requested through `DriverViewModel.requestPayout`, which calls
  // the backend ledger. There is no local equivalent on purpose.

  void updateProfile(DriverProfile profile) {
    _driverProfile = profile;
    notifyListeners();
  }
}
