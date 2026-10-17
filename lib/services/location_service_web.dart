// Web implementation of LocationService.
// Uses the browser's native navigator.geolocation API.

import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/geohash_util.dart';
import 'location_models.dart';

class LocationService {
  LocationService() {
    debugPrint('════════════════════════════════════');
    debugPrint('  [WEB FILE LOADED]  ← this is the one running on Chrome');
    debugPrint('════════════════════════════════════');
    _logEnvironment();
  }

  void _logEnvironment() {
    try {
      final nav = html.window.navigator;
      final loc = html.window.location;
      debugPrint('[WEB] userAgent          = ${nav.userAgent}');
      final dynamic geoObj = nav.geolocation;
      debugPrint('[WEB] hasGeolocation?    = ${geoObj != null}');
      debugPrint('[WEB] location.protocol  = ${loc.protocol}');
      debugPrint('[WEB] location.host      = ${loc.host}');
      debugPrint('[WEB] location.hostname  = ${loc.hostname}');
      debugPrint('[WEB] isSecureContext    = ${html.window.isSecureContext}');
    } catch (e) {
      debugPrint('[WEB] _logEnvironment failed: $e');
    }
  }

  final StreamController<LocationUpdate> _controller =
      StreamController<LocationUpdate>.broadcast();

  StreamSubscription<dynamic>? _watchSub;
  bool _isBroadcasting = false;
  bool _hasRealFix = false;

  double _currentLat = AppConstants.defaultLat;
  double _currentLng = AppConstants.defaultLng;
  double _currentHeading = 0.0;

  bool simulateMovementForDemo = false;

  Stream<LocationUpdate> get locationStream => _controller.stream;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  double get currentHeading => _currentHeading;
  bool get isBroadcasting => _isBroadcasting;
  bool get hasRealFix => _hasRealFix;

  Future<bool> checkPermission() async {
    debugPrint('[WEB] checkPermission: called');
    try {
      final dynamic nav = html.window.navigator;
      final dynamic perms = nav.permissions;
      if (perms == null) {
        debugPrint('[WEB] checkPermission: Permissions API not available');
        return false;
      }
      final dynamic status = await perms.query({'name': 'geolocation'});
      debugPrint('[WEB] checkPermission: state=${status?.state}');
      return status?.state == 'granted';
    } catch (e) {
      debugPrint('[WEB] checkPermission: threw $e');
      return false;
    }
  }

  Future<bool> requestPermission() async {
    debugPrint('[WEB] requestPermission: called');
    final r = await fetchCurrentPositionDetailed();
    debugPrint('[WEB] requestPermission: result=${r.status}');
    return r.status == LocationFetchStatus.ok ||
        r.status == LocationFetchStatus.timeout;
  }

  Future<LocationFetchResult> fetchCurrentPositionDetailed() async {
    debugPrint('[WEB] ═══ fetchCurrentPositionDetailed: START ═══');
    try {
      final dynamic geo = html.window.navigator.geolocation;
      debugPrint('[WEB] geolocation object: $geo');
      if (geo == null) {
        debugPrint('[WEB] ✗ geolocation is NULL — browser refuses to expose it');
        debugPrint('[WEB]   Common causes:');
        debugPrint('[WEB]   - Not on http://localhost or https:// (insecure origin)');
        debugPrint('[WEB]   - Browser flags disabled geolocation globally');
        return const LocationFetchResult(LocationFetchStatus.error);
      }

      debugPrint('[WEB] calling geo.getCurrentPosition()...');
      debugPrint('[WEB]   (Chrome SHOULD prompt you now if permission is undecided)');

      final dynamic pos = await geo
          .getCurrentPosition()
          .timeout(const Duration(seconds: 18));

      debugPrint('[WEB] ✓ getCurrentPosition returned: $pos');
      final result = _extractResult(pos);
      debugPrint('[WEB] extract result: status=${result.status}');
      return result;
    } on TimeoutException {
      debugPrint('[WEB] ✗ TIMEOUT after 18s');
      debugPrint('[WEB]   Chrome never answered the geolocation call.');
      debugPrint('[WEB]   Usually: prompt is hidden, or permission is Blocked.');
      return const LocationFetchResult(LocationFetchStatus.timeout);
    } catch (e, st) {
      debugPrint('[WEB] ✗ EXCEPTION: $e');
      debugPrint('[WEB]   runtimeType: ${e.runtimeType}');
      debugPrint('[WEB]   stack: $st');
      final code = _errorCode(e);
      debugPrint('[WEB]   extracted error code: $code  '
          '(1=denied, 2=unavailable, 3=timeout)');
      if (code != null) {
        final status = code == 1
            ? LocationFetchStatus.permissionDenied
            : (code == 3
                ? LocationFetchStatus.timeout
                : LocationFetchStatus.error);
        return LocationFetchResult(status);
      }
      return const LocationFetchResult(LocationFetchStatus.error);
    }
  }

  LocationFetchResult _extractResult(dynamic pos) {
    debugPrint('[WEB] _extractResult: pos=$pos');
    if (pos == null) {
      debugPrint('[WEB] _extractResult: pos is null');
      return const LocationFetchResult(LocationFetchStatus.error);
    }
    final dynamic coords = pos.coords;
    debugPrint('[WEB] _extractResult: coords=$coords');
    if (coords == null) {
      debugPrint('[WEB] _extractResult: coords is null');
      return const LocationFetchResult(LocationFetchStatus.error);
    }

    debugPrint('[WEB]   coords.latitude  = ${coords.latitude}');
    debugPrint('[WEB]   coords.longitude = ${coords.longitude}');
    debugPrint('[WEB]   coords.heading   = ${coords.heading}');
    debugPrint('[WEB]   coords.speed     = ${coords.speed}');
    debugPrint('[WEB]   coords.accuracy  = ${coords.accuracy}');

    final double? lat = (coords.latitude as num?)?.toDouble();
    final double? lng = (coords.longitude as num?)?.toDouble();
    if (lat == null || lng == null) {
      debugPrint('[WEB] _extractResult: lat or lng is null');
      return const LocationFetchResult(LocationFetchStatus.error);
    }

    _currentLat = lat;
    _currentLng = lng;
    _currentHeading = (coords.heading as num?)?.toDouble() ?? 0.0;
    _hasRealFix = true;

    debugPrint('[WEB] ✓✓✓ FIX ACQUIRED: $lat, $lng  heading=$_currentHeading');

    return LocationFetchResult(
      LocationFetchStatus.ok,
      NativeLocationPoint(
        latitude: lat,
        longitude: lng,
        heading: _currentHeading,
        speed: (coords.speed as num?)?.toDouble() ?? 0.0,
        altitude: (coords.altitude as num?)?.toDouble() ?? 0.0,
        isMock: false,
      ),
    );
  }

  int? _errorCode(Object e) {
    try {
      final dynamic d = e;
      final dynamic code = d.code;
      if (code is int) return code;
      if (code is num) return code.toInt();
    } catch (_) {}
    return null;
  }

  Future<NativeLocationPoint?> fetchCurrentPosition() async {
    final r = await fetchCurrentPositionDetailed();
    return r.point;
  }

  Future<NativeLocationPoint?> waitForFirstFix({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    debugPrint('[WEB] waitForFirstFix: called (hasRealFix=$_hasRealFix)');
    if (_hasRealFix) {
      debugPrint('[WEB] waitForFirstFix: already have fix');
      return NativeLocationPoint(
        latitude: _currentLat,
        longitude: _currentLng,
        heading: _currentHeading,
      );
    }
    _startWatch();
    final r = await fetchCurrentPositionDetailed();
    debugPrint('[WEB] waitForFirstFix: done, status=${r.status}');
    return r.point;
  }

  Future<void> startLiveTracking() async {
    _startWatch();
  }

  void _startWatch() {
    if (_watchSub != null) return;
    try {
      final dynamic stream = html.window.navigator.geolocation.watchPosition();
      debugPrint('[WEB] _startWatch: watchPosition returned '
          'type=${stream.runtimeType}');
      if (stream is Stream) {
        _watchSub = stream.listen(
          (dynamic pos) {
            final r = _extractResult(pos);
            if (r.isOk) _emit();
          },
          onError: (Object err) {
            debugPrint('[WEB] watchPosition error: $err');
          },
        );
      } else {
        debugPrint('[WEB] _startWatch: watchPosition is NOT a Stream — '
            'this Flutter version uses the legacy int API');
      }
    } catch (e) {
      debugPrint('[WEB] _startWatch threw: $e');
    }
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(LocationUpdate(
      latitude: _currentLat,
      longitude: _currentLng,
      heading: _currentHeading,
      geohash: GeohashUtil.encode(_currentLat, _currentLng),
      timestamp: DateTime.now(),
    ));
  }

  void startBroadcasting({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {
    startDriverLocationBroadcast(interval: interval, speedKmh: speedKmh);
  }

  void stopBroadcasting() => stopDriverLocationBroadcast();

  void startDriverLocationBroadcast({
    Duration interval = const Duration(seconds: 3),
    double speedKmh = 35.0,
  }) {
    if (_isBroadcasting) return;
    _isBroadcasting = true;
    _startWatch();
  }

  void stopDriverLocationBroadcast() {
    _watchSub?.cancel();
    _watchSub = null;
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
    _emit();
  }

  void dispose() {
    stopDriverLocationBroadcast();
    _controller.close();
  }
}