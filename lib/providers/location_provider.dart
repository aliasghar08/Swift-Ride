import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../services/location_service.dart';

/// Zero-dependency Location Provider streaming live driver coordinates,
/// calculating heading rotations, and driving map animations.
class LocationProvider extends ChangeNotifier {
  final LocationService _locationService;
  StreamSubscription<LocationUpdate>? _subscription;

  double _latitude = AppConstants.defaultLat;
  double _longitude = AppConstants.defaultLng;
  double _heading = 0.0;
  bool _isBroadcasting = false;

  /// Invoked on every location update. The driver cockpit uses this to publish
  /// telemetry to the backend while a trip is active, so the rider sees the
  /// real vehicle rather than their own position.
  void Function(double latitude, double longitude, double heading)? onLocationUpdate;

  LocationProvider({
    LocationService? locationService,
    bool autoStart = true,
  }) : _locationService = locationService ?? LocationService() {
    _subscription = _locationService.locationStream.listen((update) {
      _latitude = update.latitude;
      _longitude = update.longitude;
      _heading = update.heading;
      notifyListeners();
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
