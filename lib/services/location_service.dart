import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/geohash_util.dart';
import 'native/native_channel_constants.dart';

class NativeLocationPoint {
  final double latitude;
  final double longitude;
  final double heading;
  final double speed;
  final double altitude;
  final bool isMock;

  const NativeLocationPoint({
    required this.latitude,
    required this.longitude,
    this.heading = 0.0,
    this.speed = 0.0,
    this.altitude = 0.0,
    this.isMock = false,
  });
}

class LocationUpdate {
  final double latitude;
  final double longitude;
  final double heading;
  final String geohash;
  final DateTime timestamp;

  const LocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.geohash,
    required this.timestamp,
  });
}

/// In-house native location service communicating directly via platform MethodChannels
/// to iOS CLLocationManager and Android LocationManager with zero third-party packages.
class LocationService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.locationChannel);

  Timer? _broadcastTimer;
  Timer? _pollingTimer;
  final StreamController<LocationUpdate> _locationStreamController =
      StreamController<LocationUpdate>.broadcast();

  double _currentLat = AppConstants.defaultLat;
  double _currentLng = AppConstants.defaultLng;
  double _currentHeading = 0.0;
  double _simAngle = 0.0;
  bool _isBroadcasting = false;

  /// Development-only synthetic movement. Opt-in AND hard-gated to debug builds,
  /// because it publishes invented coordinates that look like real GPS.
  bool simulateMovementForDemo = false;

  Stream<LocationUpdate> get locationStream => _locationStreamController.stream;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  double get currentHeading => _currentHeading;
  bool get isBroadcasting => _isBroadcasting;

  static Future<T?> _invokeSafe<T>(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _invokeMapSafe(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(method, arguments);
    } catch (_) {
      return null;
    }
  }

  /// Checks if location permission is granted natively.
  Future<bool> checkPermission() async {
    final res = await _invokeSafe<bool>(NativeChannelConstants.methodCheckLocationPermissions);
    // Fail closed: an unreachable channel means "unknown", never "granted".
    return res ?? false;
  }

  /// Requests location permission natively.
  Future<bool> requestPermission() async {
    final res = await _invokeSafe<bool>(NativeChannelConstants.methodRequestLocationPermissions);
    return res ?? false;
  }

  /// Acquires real current GPS coordinates directly from native platform channel.
  Future<NativeLocationPoint?> fetchCurrentPosition() async {
    try {
      await requestPermission();
      final res = await _invokeMapSafe(NativeChannelConstants.methodGetCurrentLocation);
      if (res != null) {
        final lat = (res['latitude'] as num?)?.toDouble() ?? AppConstants.defaultLat;
        final lng = (res['longitude'] as num?)?.toDouble() ?? AppConstants.defaultLng;
        final heading = (res['heading'] as num?)?.toDouble() ?? 0.0;
        final speed = (res['speed'] as num?)?.toDouble() ?? 0.0;
        final altitude = (res['altitude'] as num?)?.toDouble() ?? 0.0;
        final isMock = res['isMock'] as bool? ?? false;

        _currentLat = lat;
        _currentLng = lng;
        _currentHeading = heading;

        return NativeLocationPoint(
          latitude: lat,
          longitude: lng,
          heading: heading,
          speed: speed,
          altitude: altitude,
          isMock: isMock,
        );
      }
    } catch (e) {
      debugPrint('[LocationService] fetchCurrentPosition failed: $e');
    }

    // Return null rather than the hardcoded city centre. Previously a failed fix
    // was silently replaced with Islamabad coordinates and published as genuine
    // GPS. Callers must now handle "no fix" explicitly.
    return null;
  }

  /// Starts live native GPS updates.
  Future<void> startLiveTracking() async {
    _invokeSafe(NativeChannelConstants.methodStartLocationUpdates);

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      final loc = await fetchCurrentPosition();
      if (loc != null) {
        _currentLat = loc.latitude;
        _currentLng = loc.longitude;
        _currentHeading = loc.heading;
        _locationStreamController.add(
          LocationUpdate(
            latitude: _currentLat,
            longitude: _currentLng,
            heading: _currentHeading,
            geohash: GeohashUtil.encode(_currentLat, _currentLng),
            timestamp: DateTime.now(),
          ),
        );
      }
    });
  }

  /// Starts broadcaster (compatible with LocationProvider).
  void startBroadcasting({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {
    startDriverLocationBroadcast(interval: interval, speedKmh: speedKmh);
  }

  /// Stops broadcaster (compatible with LocationProvider).
  void stopBroadcasting() {
    stopDriverLocationBroadcast();
  }

  /// Starts periodic high-frequency telemetry broadcasting for active rides.
  void startDriverLocationBroadcast({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {
    if (_isBroadcasting) return;
    _isBroadcasting = true;

    // Real native GPS is the only source of truth.
    startLiveTracking();

    // Synthetic movement is demo scaffolding. Opt-in AND debug-only, so a
    // production build can never broadcast invented coordinates.
    if (!kDebugMode || !simulateMovementForDemo) return;

    _broadcastTimer = Timer.periodic(interval, (_) {
      _simAngle += 0.08;
      final speedFactor = speedKmh / 3600.0 * interval.inSeconds;
      final latDelta = (cos(_simAngle) * speedFactor) / 111.0;
      final lngDelta = (sin(_simAngle) * speedFactor) / 111.0;

      final prevLat = _currentLat;
      final prevLng = _currentLng;

      _currentLat += latDelta;
      _currentLng += lngDelta;

      _currentHeading = _calculateBearing(
        prevLat,
        prevLng,
        _currentLat,
        _currentLng,
      );

      final geohash = GeohashUtil.encode(_currentLat, _currentLng);

      _locationStreamController.add(
        LocationUpdate(
          latitude: _currentLat,
          longitude: _currentLng,
          heading: _currentHeading,
          geohash: geohash,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  /// Stops telemetry broadcasting.
  void stopDriverLocationBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _invokeSafe(NativeChannelConstants.methodStopLocationUpdates);
    _isBroadcasting = false;
  }

  void updatePosition(double lat, double lng, {double? heading}) {
    updateLocationManually(lat, lng, heading: heading ?? 0.0);
  }

  void updateLocationManually(double lat, double lng, {double heading = 0.0}) {
    _currentLat = lat;
    _currentLng = lng;
    _currentHeading = heading;

    _locationStreamController.add(
      LocationUpdate(
        latitude: lat,
        longitude: lng,
        heading: heading,
        geohash: GeohashUtil.encode(lat, lng),
        timestamp: DateTime.now(),
      ),
    );
  }

  static double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    final dLon = (lng2 - lng1) * (pi / 180.0);
    final lat1Rad = lat1 * (pi / 180.0);
    final lat2Rad = lat2 * (pi / 180.0);

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    final brng = atan2(y, x);
    return ((brng * (180.0 / pi)) + 360.0) % 360.0;
  }

  void dispose() {
    stopDriverLocationBroadcast();
    _locationStreamController.close();
  }
}
