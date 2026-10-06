import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../domain/models/driver_profile_model.dart';
import '../domain/models/ride_model.dart';
import '../services/admin_service.dart';
import '../services/firestore/firestore_ride_service.dart';
import '../services/firestore/firestore_driver_service.dart';

/// Admin provider backed by Cloud Functions and Firestore.
///
/// Previously this was entirely in-memory and seeded with a fabricated driver
/// applicant ("driver_sarah_303", Honda Accord), so the dashboard showed an
/// invented person an operator could "approve". KPIs were computed from the
/// current session's own ride history, which reads as an idle platform.
class AdminProvider extends ChangeNotifier {
  final AdminService _adminService;
  final FirestoreRideService _rideService;
  final FirestoreDriverService _driverService;

  List<DriverProfile> _pendingDrivers = [];
  StreamSubscription<List<DriverProfile>>? _pendingSub;

  PlatformKpis? _serverKpis;
  bool _isLoadingStats = false;
  String? _statsError;

  AdminProvider({
    AdminService? adminService,
    FirestoreDriverService? driverService,
    FirestoreRideService? rideService,
  })  : _adminService = adminService ?? AdminService(),
        _driverService = driverService ?? FirestoreDriverService(),
        _rideService = rideService ?? FirestoreRideService();

  List<DriverProfile> get pendingDrivers => List.unmodifiable(_pendingDrivers);
  bool get isLoadingStats => _isLoadingStats;
  String? get statsError => _statsError;

  /// True once real platform KPIs have been loaded from the backend.
  bool get hasServerStats => _serverKpis != null;

  /// Subscribes to the live queue of driver applications awaiting review.
  void watchPendingDrivers() {
    _pendingSub ??= _driverService.streamPendingDrivers().listen(
      (drivers) {
        _pendingDrivers = drivers;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('[AdminProvider] pending drivers stream failed: $e');
      },
    );
  }

  List<RideModel> _platformRides = [];
  bool _isLoadingRides = false;
  String? _ridesError;

  /// Recent platform-wide rides for the admin console.
  List<RideModel> get platformRides => List.unmodifiable(_platformRides);
  bool get isLoadingRides => _isLoadingRides;
  String? get ridesError => _ridesError;

  /// Loads recent platform-wide rides via the `getAdminRides` Cloud Function.
  ///
  /// This function existed and was never called: the console's ride log was fed
  /// from the signed-in admin's own ride history instead.
  Future<void> loadPlatformRides({String? status, int limit = 50}) async {
    if (_isLoadingRides) return;

    _isLoadingRides = true;
    _ridesError = null;
    notifyListeners();

    final page = await _rideService.fetchAdminRides(status: status, limit: limit);

    _platformRides = page.rides;
    _ridesError = page.error;
    _isLoadingRides = false;
    notifyListeners();
  }

  /// Loads real platform KPIs from the `getDashboardStats` Cloud Function.
  Future<void> loadStats() async {
    if (Firebase.apps.isEmpty) {
      _statsError = 'Dashboard metrics need an internet connection.';
      notifyListeners();
      return;
    }

    _isLoadingStats = true;
    _statsError = null;
    notifyListeners();

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('getDashboardStats').call();
      _serverKpis = PlatformKpis.fromServer(res.data as Map<String, dynamic>);
    } on FirebaseFunctionsException catch (e) {
      _statsError = switch (e.code) {
        'permission-denied' => 'Your account does not have admin access.',
        'unauthenticated' => 'Please sign in again.',
        'unavailable' => 'The dashboard is unreachable right now. Pull to retry.',
        _ => 'We could not load dashboard metrics.',
      };
    } catch (e) {
      debugPrint('[AdminProvider] loadStats failed: $e');
      _statsError = 'We could not load dashboard metrics.';
    } finally {
      _isLoadingStats = false;
      notifyListeners();
    }
  }

  /// Approves or rejects a driver's application through the backend.
  ///
  /// The application is only removed from the local queue once the server
  /// confirms the change. Returns true on success.
  Future<bool> verifyDriver(String driverId, bool approved, {String? notes}) async {
    if (Firebase.apps.isEmpty) return false;

    try {
      await FirebaseFunctions.instance.httpsCallable('verifyDriver').call(
        <String, dynamic>{
          'driverId': driverId,
          'approved': approved,
          'notes': ?notes,
        },
      );
      _pendingDrivers = _pendingDrivers.where((d) => d.userId != driverId).toList();
      notifyListeners();
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[AdminProvider] verifyDriver failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[AdminProvider] verifyDriver failed: $e');
      return false;
    }
  }

  /// Platform KPIs — server aggregates when loaded, otherwise a local estimate.
  PlatformKpis getKpis({
    required List<RideModel> rideHistory,
    required RideModel? currentRide,
    required List<DriverProfile> allDrivers,
  }) {
    final server = _serverKpis;
    if (server != null) return server;

    return _adminService.computePlatformKpis(
      rideHistory: rideHistory,
      currentRide: currentRide,
      allDrivers: allDrivers,
      pendingDrivers: _pendingDrivers,
    );
  }

  @override
  void dispose() {
    _pendingSub?.cancel();
    super.dispose();
  }
}
