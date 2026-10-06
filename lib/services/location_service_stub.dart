// Fallback used only when neither dart.library.io nor a web library is
// available. Never reports a fix.

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'location_models.dart';

class LocationService {
  LocationService() {
    debugPrint('════ [STUB FILE LOADED] ════');
  }

  final StreamController<LocationUpdate> _controller =
      StreamController<LocationUpdate>.broadcast();

  bool simulateMovementForDemo = false;

  Stream<LocationUpdate> get locationStream => _controller.stream;
  double get currentLat => AppConstants.defaultLat;
  double get currentLng => AppConstants.defaultLng;
  double get currentHeading => 0.0;
  bool get isBroadcasting => false;
  bool get hasRealFix => false;

  Future<bool> checkPermission() async => false;
  Future<bool> requestPermission() async => false;

  Future<LocationFetchResult> fetchCurrentPositionDetailed() async =>
      const LocationFetchResult(LocationFetchStatus.error);

  Future<NativeLocationPoint?> fetchCurrentPosition() async => null;

  Future<NativeLocationPoint?> waitForFirstFix({
    Duration timeout = const Duration(seconds: 15),
  }) async => null;

  Future<void> startLiveTracking() async {}

  void startBroadcasting({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {}

  void stopBroadcasting() {}

  void startDriverLocationBroadcast({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {}

  void stopDriverLocationBroadcast() {}

  void updatePosition(double lat, double lng, {double? heading}) {}

  void updateLocationManually(double lat, double lng, {double heading = 0.0}) {}

  void dispose() => _controller.close();
}