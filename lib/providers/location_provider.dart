import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:swiftride/services/location_service.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/geohash_util.dart';
import '../domain/models/location_point_model.dart';
import '../services/coordinate_parser.dart';
import '../services/map_service.dart';
import '../services/native_map_service.dart';

enum LocationTrackingMode { idle, balanced, highAccuracy }

/// Streams live driver coordinates, calculates heading rotations, and drives
/// map animations. Also exposes [hasRealFix] so the UI can distinguish "still
/// waiting for GPS" from "we have coordinates to show".
class LocationProvider extends ChangeNotifier {
  final LocationService _locationService;
  StreamSubscription<LocationUpdate>? _subscription;

  double _latitude = AppConstants.defaultLat;
  double _longitude = AppConstants.defaultLng;
  double _heading = 0.0;
  double _speed = 0.0;
  bool _isBroadcasting = false;
  bool _hasRealFix = false;
  String _address = '';
  NativeGeocodedAddress? _detailedAddress;
  double _lastGeotaggedLat = 0.0;
  double _lastGeotaggedLng = 0.0;
  LocationTrackingMode _trackingMode = LocationTrackingMode.balanced;

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
      _speed = update.speed;
      final wasFirst = !_hasRealFix;
      _hasRealFix = true;
      notifyListeners();
      if (wasFirst) {
        debugPrint('[LocationProvider] first real fix: '
            '${update.latitude.toStringAsFixed(5)}, '
            '${update.longitude.toStringAsFixed(5)}');
      }

      // Asynchronously resolve human-readable geotagged address when moved > 50m
      // or when current address is empty / non-granular (e.g. bare "Jhang")
      final needsResolution = _address.isEmpty ||
          !NativeMapService.isGranularAddress(_address) ||
          GeohashUtil.distanceKm(_latitude, _longitude, _lastGeotaggedLat, _lastGeotaggedLng) > 0.05;

      if (needsResolution) {
        _lastGeotaggedLat = _latitude;
        _lastGeotaggedLng = _longitude;
        MapService.instance.reverseGeocodeDetailed(_latitude, _longitude).then((detailed) {
          if (detailed != null) {
            final trimmed = detailed.formattedAddress.trim();
            if (trimmed.isNotEmpty &&
                !trimmed.startsWith('Location (') &&
                !trimmed.startsWith('Pinned Spot')) {
              // Never overwrite an already-granular address with a bare city or non-granular fallback
              if (detailed.isGranular ||
                  NativeMapService.isGranularAddress(trimmed) ||
                  _address.isEmpty ||
                  !NativeMapService.isGranularAddress(_address)) {
                _detailedAddress = detailed;
                _address = trimmed;
                notifyListeners();
              }
            }
          }
        }).catchError((_) {});
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
  double get speed => _speed;
  bool get isBroadcasting => _isBroadcasting;
  bool get hasRealFix => _hasRealFix;
  String get address => _address;
  NativeGeocodedAddress? get detailedAddress => _detailedAddress;

  /// Visible for testing to seed geocoded details.
  @visibleForTesting
  void setDetailedAddressForTesting(NativeGeocodedAddress detailed) {
    _detailedAddress = detailed;
    _address = detailed.formattedAddress;
    notifyListeners();
  }

  /// Resolved city of current location (defaults to 'Jhang' if unavailable).
  String get currentCity {
    final detailedCity = _detailedAddress?.city.trim();
    if (detailedCity != null && detailedCity.isNotEmpty) {
      return detailedCity;
    }
    if (_address.isNotEmpty) {
      final parts = _address.split(',');
      if (parts.length >= 2) {
        final candidate = parts[parts.length - 2].trim();
        if (candidate.isNotEmpty && !candidate.toLowerCase().contains('pakistan')) {
          return candidate;
        }
      }
    }
    return 'Jhang';
  }

  /// Resolved area or neighborhood of current location.
  String get currentArea {
    final neighborhood = _detailedAddress?.neighborhood.trim();
    if (neighborhood != null && neighborhood.isNotEmpty) {
      return neighborhood;
    }
    final street = _detailedAddress?.street.trim();
    if (street != null && street.isNotEmpty) {
      return street;
    }
    return '';
  }

  /// Current location encoded as a precision-7 geohash.
  String get geohash => GeohashUtil.encode(_latitude, _longitude, 7);

  /// Current location formatted as a geotagged [LocationPoint].
  LocationPoint get locationPoint => LocationPoint.withGeotag(
        latitude: _latitude,
        longitude: _longitude,
        address: _address.isNotEmpty
            ? _address
            : CoordinateParser.formatOfflineGeotag(_latitude, _longitude),
      );

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
      _latitude = fix.latitude;
      _longitude = fix.longitude;
      _heading = fix.heading;
      _speed = fix.speed;
      unawaited(refreshAddress(force: true));
      notifyListeners();
    }
    return fix;
  }

  /// Resolves the current coordinates to a human-readable street/plot address via MapService.
  Future<String> refreshAddress({bool force = false}) async {
    if (!force && _address.isNotEmpty && NativeMapService.isGranularAddress(_address)) {
      return _address;
    }
    try {
      final detailed = await MapService.instance.reverseGeocodeDetailed(_latitude, _longitude);
      if (detailed != null) {
        final trimmed = detailed.formattedAddress.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.startsWith('Location (') &&
            !trimmed.startsWith('Pinned Spot')) {
          if (detailed.isGranular ||
              NativeMapService.isGranularAddress(trimmed) ||
              _address.isEmpty ||
              !NativeMapService.isGranularAddress(_address)) {
            _detailedAddress = detailed;
            _address = trimmed;
            notifyListeners();
          }
        }
      }
    } catch (_) {}
    return _address;
  }

  /// Whether foreground location permission is currently granted.
  Future<bool> hasPermission() => _locationService.checkPermission();

  /// `null` when no native location platform is available (unit tests).
  Future<bool?> permissionStatus() => _locationService.permissionStatus();

  /// Launches the OS runtime location prompt. Call ONLY from the "Continue"
  /// button of the in-app prominent disclosure (see PermissionDisclosures).
  Future<bool> requestPermission() async {
    final granted = await _locationService.requestPermission();
    if (granted) {
      // Kick an immediate fix now that we are allowed to read GPS.
      unawaited(_locationService.startLiveTracking());
    }
    return granted;
  }

  /// Whether background ("all the time") location permission is currently granted.
  Future<bool> hasBackgroundPermission() =>
      _locationService.checkBackgroundPermission();

  /// `null` when no native location platform is available (unit tests).
  Future<bool?> backgroundPermissionStatus() =>
      _locationService.backgroundPermissionStatus();

  /// Launches the OS background location permission prompt. Call ONLY from the
  /// "Continue" button of the in-app background location prominent disclosure.
  Future<bool> requestBackgroundPermission() =>
      _locationService.requestBackgroundPermission();

  LocationTrackingMode get trackingMode => _trackingMode;

  /// Sets adaptive GPS polling mode to preserve battery.
  /// Use [LocationTrackingMode.highAccuracy] during active trips or online driver navigation;
  /// use [LocationTrackingMode.balanced] during idle map browsing or rider destination entry.
  void setTrackingMode(LocationTrackingMode mode) {
    if (_trackingMode == mode) return;
    _trackingMode = mode;
    if (_isBroadcasting) {
      if (mode == LocationTrackingMode.idle) {
        _locationService.stopLiveTracking();
      } else {
        _locationService.startLiveTracking(
          mode: mode == LocationTrackingMode.highAccuracy
              ? 'high_accuracy'
              : 'balanced',
        );
      }
    }
  }

  /// Pauses continuous satellite tracking when the app is obscured/backgrounded.
  void pauseTracking() {
    _locationService.stopLiveTracking();
  }

  /// Resumes adaptive tracking when returning to foreground.
  void resumeTracking() {
    if (_trackingMode != LocationTrackingMode.idle && _isBroadcasting) {
      _locationService.startLiveTracking(
        mode: _trackingMode == LocationTrackingMode.highAccuracy
            ? 'high_accuracy'
            : 'balanced',
      );
    }
  }

  void startBroadcaster({LocationTrackingMode mode = LocationTrackingMode.balanced}) {
    _trackingMode = mode;
    _locationService.startLiveTracking(
      mode: mode == LocationTrackingMode.highAccuracy
          ? 'high_accuracy'
          : 'balanced',
    );
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