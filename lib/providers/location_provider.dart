import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:swiftride/services/location_models.dart';
import 'package:swiftride/services/location_service.dart';
import '../core/constants/app_constants.dart';

/// Streams live driver coordinates, calculates heading rotations, and drives
/// map animations. Also exposes [hasRealFix] so the UI can distinguish "still
/// waiting for GPS" from "we have coordinates to show".
class LocationProvider extends ChangeNotifier {
  final LocationService _locationService;
  StreamSubscription<LocationUpdate>? _subscription;

  double _latitude = AppConstants.defaultLat;
  double _longitude = AppConstants.defaultLng;
  double _heading = 0.0;
  bool _isBroadcasting = false;
  bool _hasRealFix = false;

  /// Invoked on every location update. The driver cockpit uses this to publish
  /// telemetry to the backend while a trip is active.
  void Function(double latitude, double longitude, double heading)? onLocationUpdate;

  LocationProvider({
    LocationService? locationService,
    bool autoStart = true,
  }) : _locationService = locationService ?? LocationService() {
    _hasRealFix = _locationService.hasRealFix;

    _subscription = _locationService.locationStream.listen((update) {
      _latitude = update.latitude;
      _longitude = update.longitude;
      _heading = update.heading;
      final wasFirst = !_hasRealFix;
      _hasRealFix = true;
      notifyListeners();
      if (wasFirst) {
        debugPrint('[LocationProvider] first real fix: '
            '${update.latitude.toStringAsFixed(5)}, '
            '${update.longitude.toStringAsFixed(5)}');
      }
      onLocationUpdate?.call(update.latitude, update.longitude, update.heading);
    });

    if (autoStart) {
      startBroadcaster();
    }
  }

  double get latitude => _latitude;
  double get longitude => _longitude;
  double get heading => _heading;
  bool get isBroadcasting => _isBroadcasting;
  bool get hasRealFix => _hasRealFix;

  /// Waits for the first genuine GPS fix (or times out). Returns null on
  /// timeout / denied permission. Callers should not fall back to invented
  /// coordinates on null — they should show an error state.
  Future<NativeLocationPoint?> waitForFirstFix({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_hasRealFix) {
      return NativeLocationPoint(
        latitude: _latitude,
        longitude: _longitude,
        heading: _heading,
      );
    }
    final fix = await _locationService.waitForFirstFix(timeout: timeout);
    if (fix != null) {
      _hasRealFix = true;
      notifyListeners();
    }
    return fix;
  }

  void startBroadcaster() {
    _locationService.startBroadcasting();
    _isBroadcasting = true;
    notifyListeners();
  }

  void stopBroadcaster() {
    _locationService.stopBroadcasting();
    _isBroadcasting = false;
    notifyListeners();
  }

  void updatePosition(double lat, double lng, {double? heading}) {
    _latitude = lat;
    _longitude = lng;
    if (heading != null) _heading = heading;
    _hasRealFix = true;
    _locationService.updatePosition(lat, lng, heading: heading);
    notifyListeners();
  }

  @override
  void dispose() {
    stopBroadcaster();
    _subscription?.cancel();
    _locationService.dispose();
    super.dispose();
  }
}