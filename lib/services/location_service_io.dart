// Native (iOS + Android) implementation of LocationService.
//
// Talks to the platform MethodChannel registered in AppDelegate.swift (iOS)
// and MainActivity.kt (Android). Compiled only when dart.library.io is
// available — i.e. on real native targets, not on web.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/geohash_util.dart';
import 'location_models.dart';
import 'native/native_channel_constants.dart';

class LocationService {
  LocationService() {
    debugPrint('════ [IO FILE LOADED] ════');
  }

  static const MethodChannel _channel =
      MethodChannel(NativeChannelConstants.locationChannel);

  Timer? _broadcastTimer;
  Timer? _pollingTimer;
  final StreamController<LocationUpdate> _locationStreamController =
      StreamController<LocationUpdate>.broadcast();

  double _currentLat = AppConstants.defaultLat;
  double _currentLng = AppConstants.defaultLng;
  double _currentHeading = 0.0;
  double _simAngle = 0.0;
  bool _isBroadcasting = false;
  bool _hasRealFix = false;

  /// Development-only synthetic movement. Opt-in AND hard-gated to debug
  /// builds — a release build can never publish invented coordinates.
  bool simulateMovementForDemo = false;

  Stream<LocationUpdate> get locationStream => _locationStreamController.stream;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  double get currentHeading => _currentHeading;
  bool get isBroadcasting => _isBroadcasting;

  /// True once we have received a genuine GPS fix from the platform.
  bool get hasRealFix => _hasRealFix;

  static Future<T?> _invokeSafe<T>(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // No native handler registered. This is normal during unit tests
      // (flutter test runs in a headless Dart VM with no Flutter engine)
      // and on any platform where the native side has not been wired up.
      // Stay silent so test output stays readable.
      return null;
    } on PlatformException catch (e) {
      debugPrint('[LocationService.io] $method failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[LocationService.io] $method failed: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _invokeMapSafe(
    String method, [
    dynamic arguments,
  ]) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[LocationService.io] $method failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[LocationService.io] $method failed: $e');
      return null;
    }
  }

  Future<bool> checkPermission() async {
    final res = await _invokeSafe<bool>(
      NativeChannelConstants.methodCheckLocationPermissions,
    );
    return res ?? false; // fail closed
  }

  Future<bool> requestPermission() async {
    final res = await _invokeSafe<bool>(
      NativeChannelConstants.methodRequestLocationPermissions,
    );
    return res ?? false;
  }

  /// Single-shot fetch with explicit status. Never invents coordinates.
  Future<LocationFetchResult> fetchCurrentPositionDetailed() async {
    var hasPermission = await checkPermission();
    if (!hasPermission) {
      hasPermission = await requestPermission();
      if (!hasPermission) {
        return const LocationFetchResult(LocationFetchStatus.permissionDenied);
      }
    }

    final res = await _invokeMapSafe(
      NativeChannelConstants.methodGetCurrentLocation,
    );
    if (res == null) {
      // Either the platform call failed, permission was denied, or it timed
      // out. Re-check the permission bit so we can tell them apart.
      final granted = await checkPermission();
      return LocationFetchResult(
        granted
            ? LocationFetchStatus.timeout
            : LocationFetchStatus.permissionDenied,
      );
    }

    final lat = (res['latitude'] as num?)?.toDouble();
    final lng = (res['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      return const LocationFetchResult(LocationFetchStatus.error);
    }

    final heading = (res['heading'] as num?)?.toDouble() ?? 0.0;
    final speed = (res['speed'] as num?)?.toDouble() ?? 0.0;
    final altitude = (res['altitude'] as num?)?.toDouble() ?? 0.0;
    final isMock = res['isMock'] as bool? ?? false;

    _currentLat = lat;
    _currentLng = lng;
    _currentHeading = heading;
    _hasRealFix = true;

    return LocationFetchResult(
      LocationFetchStatus.ok,
      NativeLocationPoint(
        latitude: lat,
        longitude: lng,
        heading: heading,
        speed: speed,
        altitude: altitude,
        isMock: isMock,
      ),
    );
  }

  /// Convenience wrapper that returns null instead of a status. Kept for
  /// backwards compatibility with existing callers.
  Future<NativeLocationPoint?> fetchCurrentPosition() async {
    final r = await fetchCurrentPositionDetailed();
    return r.point;
  }

  /// Resolves on the first real GPS fix, or null on timeout / denial.
  Future<NativeLocationPoint?> waitForFirstFix({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_hasRealFix) {
      return NativeLocationPoint(
        latitude: _currentLat,
        longitude: _currentLng,
        heading: _currentHeading,
      );
    }

    // Ensure location permission is requested before waiting for fix
    final hasPerm = await checkPermission();
    if (!hasPerm) {
      await requestPermission();
    }

    final completer = Completer<NativeLocationPoint?>();
    late StreamSubscription<LocationUpdate> sub;

    sub = locationStream.listen((u) {
      if (!completer.isCompleted) {
        _hasRealFix = true;
        completer.complete(
          NativeLocationPoint(
            latitude: u.latitude,
            longitude: u.longitude,
            heading: u.heading,
          ),
        );
        sub.cancel();
      }
    });

    // Kick off tracking so we actually receive updates.
    await startLiveTracking();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
        sub.cancel();
      }
    });

    return completer.future;
  }

  Future<void> startLiveTracking() async {
    await _invokeSafe(NativeChannelConstants.methodStartLocationUpdates);

    // Fetch immediately so callers do not wait 4s for the first tick
    fetchCurrentPositionDetailed().then((r) {
      if (r.isOk) {
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

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      final r = await fetchCurrentPositionDetailed();
      if (r.isOk) {
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

  void stopLiveTracking() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _invokeSafe(NativeChannelConstants.methodStopLocationUpdates);
  }

  void startBroadcasting({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {
    startDriverLocationBroadcast(interval: interval, speedKmh: speedKmh);
  }

  void stopBroadcasting() {
    stopDriverLocationBroadcast();
  }

  void startDriverLocationBroadcast({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {
    if (_isBroadcasting) return;
    _isBroadcasting = true;

    startLiveTracking();

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

      _currentHeading =
          _calculateBearing(prevLat, prevLng, _currentLat, _currentLng);

      _locationStreamController.add(
        LocationUpdate(
          latitude: _currentLat,
          longitude: _currentLng,
          heading: _currentHeading,
          geohash: GeohashUtil.encode(_currentLat, _currentLng),
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  void stopDriverLocationBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    stopLiveTracking();
    _isBroadcasting = false;
  }

  void updatePosition(double lat, double lng, {double? heading}) {
    updateLocationManually(lat, lng, heading: heading ?? 0.0);
  }

  void updateLocationManually(double lat, double lng, {double heading = 0.0}) {
    _currentLat = lat;
    _currentLng = lng;
    _currentHeading = heading;
    _hasRealFix = true;

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

  static double _calculateBearing(
      double lat1, double lng1, double lat2, double lng2) {
    final dLon = (lng2 - lng1) * (pi / 180.0);
    final lat1Rad = lat1 * (pi / 180.0);
    final lat2Rad = lat2 * (pi / 180.0);

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    final brng = atan2(y, x);
    return ((brng * (180.0 / pi)) + 360.0) % 360.0;
  }

  void dispose() {
    stopDriverLocationBroadcast();
    _locationStreamController.close();
  }
}