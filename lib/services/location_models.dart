/// Shared location data types used by every platform implementation of
/// LocationService (io, web, stub).

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

enum LocationFetchStatus { ok, permissionDenied, timeout, error }

class LocationFetchResult {
  final LocationFetchStatus status;
  final NativeLocationPoint? point;
  const LocationFetchResult(this.status, [this.point]);

  bool get isOk => status == LocationFetchStatus.ok && point != null;
}