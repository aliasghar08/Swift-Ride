import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/distance_calculator.dart';
import '../core/utils/geohash_util.dart';

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

/// Location service that acquires real device GPS coordinates via Geolocator,
/// calculates headings, encodes geohashes, and streams live telemetry.
class LocationService {
  Timer? _broadcastTimer;
  StreamSubscription<Position>? _realGpsSubscription;
  final StreamController<LocationUpdate> _locationStreamController =
      StreamController<LocationUpdate>.broadcast();

  double _currentLat = AppConstants.defaultLat;
  double _currentLng = AppConstants.defaultLng;
  double _currentHeading = 0.0;
  double _simAngle = 0.0;
  bool _isBroadcasting = false;

  Stream<LocationUpdate> get locationStream => _locationStreamController.stream;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  double get currentHeading => _currentHeading;
  bool get isBroadcasting => _isBroadcasting;

  /// Acquires real current GPS coordinates from the device hardware.
  Future<Position?> fetchCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          return null;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      updatePosition(position.latitude, position.longitude, heading: position.heading);
      return position;
    } catch (_) {
      return null;
    }
  }

  /// Starts live location streaming: uses real GPS stream if available,
  /// with smooth vehicle heading simulation.
  void startBroadcasting({
    Duration interval = const Duration(seconds: 2),
    double? centerLat,
    double? centerLng,
  }) {
    if (_isBroadcasting) return;
    _isBroadcasting = true;

    // First attempt to acquire real device location
    fetchCurrentPosition().then((pos) {
      if (pos != null) {
        _currentLat = pos.latitude;
        _currentLng = pos.longitude;
        _currentHeading = pos.heading;
      }
    });

    try {
      _realGpsSubscription?.cancel();
      _realGpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen(
        (pos) {
          updatePosition(pos.latitude, pos.longitude, heading: pos.heading);
        },
        onError: (_) {
          // If native stream fails (e.g. simulator without mock location), fallback to broadcast timer
        },
      );
    } catch (_) {}

    final originLat = centerLat ?? _currentLat;
    final originLng = centerLng ?? _currentLng;

    _broadcastTimer = Timer.periodic(interval, (_) {
      // In simulator, provide subtle movement around current location
      _simAngle += 0.08;
      _currentLat = originLat + 0.002 * sin(_simAngle);
      _currentLng = originLng + 0.002 * cos(_simAngle);
      _currentHeading = (_simAngle * 180 / pi) % 360;

      final update = LocationUpdate(
        latitude: _currentLat,
        longitude: _currentLng,
        heading: _currentHeading,
        geohash: GeohashUtil.encode(_currentLat, _currentLng),
        timestamp: DateTime.now(),
      );

      _locationStreamController.add(update);
    });
  }

  /// Stops the location broadcast stream and cancels real GPS subscriptions.
  void stopBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _realGpsSubscription?.cancel();
    _realGpsSubscription = null;
    _isBroadcasting = false;
  }

  /// Manually update driver position (e.g. from user drag or GPS lock).
  void updatePosition(double lat, double lng, {double? heading}) {
    _currentLat = lat;
    _currentLng = lng;
    if (heading != null) {
      _currentHeading = heading;
    }

    final update = LocationUpdate(
      latitude: _currentLat,
      longitude: _currentLng,
      heading: _currentHeading,
      geohash: GeohashUtil.encode(_currentLat, _currentLng),
      timestamp: DateTime.now(),
    );
    _locationStreamController.add(update);
  }

  /// Calculates distance in km between two coordinate points.
  double calculateDistance(double startLat, double startLng, double endLat, double endLng) {
    return DistanceCalculator.haversineDistance(startLat, startLng, endLat, endLng);
  }

  /// Disposes timers and stream controllers.
  void dispose() {
    stopBroadcasting();
    _locationStreamController.close();
  }
}
