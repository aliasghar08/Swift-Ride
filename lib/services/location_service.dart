import 'dart:async';
import 'dart:math';
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

/// Zero-dependency location service that manages GPS coordinates,
/// calculates headings, encodes geohashes, and simulates RTDB driver location streams.
class LocationService {
  Timer? _broadcastTimer;
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

  /// Starts high-frequency simulated RTDB location broadcast (~2s interval).
  void startBroadcasting({
    Duration interval = const Duration(seconds: 2),
    double centerLat = AppConstants.defaultLat,
    double centerLng = AppConstants.defaultLng,
  }) {
    if (_isBroadcasting) return;
    _isBroadcasting = true;

    _broadcastTimer = Timer.periodic(interval, (_) {
      _simAngle += 0.08;
      _currentLat = centerLat + 0.005 * sin(_simAngle);
      _currentLng = centerLng + 0.005 * cos(_simAngle);
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

  /// Stops the location broadcast stream.
  void stopBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
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
