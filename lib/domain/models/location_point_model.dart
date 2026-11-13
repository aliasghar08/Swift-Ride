import '../../core/utils/geohash_util.dart';
import '../../services/coordinate_parser.dart';

class LocationPoint {
  final double latitude;
  final double longitude;
  final String address;
  final String geohash;

  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.address,
    this.geohash = '',
  });

  /// Factory constructor guaranteeing an auto-computed geohash if not explicitly provided.
  factory LocationPoint.withGeotag({
    required double latitude,
    required double longitude,
    required String address,
    String? geohash,
    int precision = 7,
  }) {
    return LocationPoint(
      latitude: latitude,
      longitude: longitude,
      address: address,
      geohash: (geohash != null && geohash.isNotEmpty)
          ? geohash
          : GeohashUtil.encode(latitude, longitude, precision),
    );
  }

  LocationPoint copyWith({
    double? latitude,
    double? longitude,
    String? address,
    String? geohash,
  }) {
    return LocationPoint(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      geohash: geohash ?? this.geohash,
    );
  }

  /// Returns the stored geohash if non-empty, otherwise lazily computes a precision-7 geohash.
  String get effectiveGeohash =>
      geohash.isNotEmpty ? geohash : GeohashUtil.encode(latitude, longitude, 7);

  /// Computes distance in kilometers to another [LocationPoint].
  double distanceTo(LocationPoint other) =>
      GeohashUtil.distanceKm(latitude, longitude, other.latitude, other.longitude);

  /// Computes initial compass bearing in degrees [0, 360) to another [LocationPoint].
  double bearingTo(LocationPoint other) =>
      GeohashUtil.bearing(latitude, longitude, other.latitude, other.longitude);

  Map<String, dynamic> toMap() => {
        'geopoint': {'latitude': latitude, 'longitude': longitude},
        'address': address,
        'geohash': effectiveGeohash,
      };

  /// Formats location metadata for Firestore document payloads.
  Map<String, dynamic> toGeotagMap() => {
        'geopoint': {'latitude': latitude, 'longitude': longitude},
        'address': address,
        'geohash': effectiveGeohash,
      };

  static num? _parseNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  factory LocationPoint.fromMap(Map<String, dynamic> map) {
    num? lat;
    num? lng;

    final geo = map['geopoint'];
    if (geo is Map) {
      lat = _parseNum(geo['latitude'] ?? geo['lat']);
      lng = _parseNum(geo['longitude'] ?? geo['lng']);
    } else if (geo != null) {
      // Handles cloud_firestore GeoPoint object dynamically without forcing compile-time dependency
      try {
        lat = _parseNum((geo as dynamic).latitude);
        lng = _parseNum((geo as dynamic).longitude);
      } catch (_) {}
    }

    lat ??= _parseNum(map['latitude'] ?? map['lat']);
    lng ??= _parseNum(map['longitude'] ?? map['lng']);

    // No silent fallback. A point without coordinates is corrupt, and
    // substituting a hardcoded city centre silently relocated real users to
    // Islamabad. Callers must handle this explicitly.
    if (lat == null || lng == null) {
      throw const FormatException('LocationPoint is missing coordinates');
    }

    final double validLat = lat.toDouble();
    final double validLng = lng.toDouble();

    final rawGeohash = map['geohash']?.toString();
    final geohash = (rawGeohash != null && rawGeohash.isNotEmpty)
        ? rawGeohash
        : GeohashUtil.encode(validLat, validLng, 7);

    final rawAddress = map['address']?.toString().trim() ?? '';
    final address = (rawAddress.isNotEmpty && !rawAddress.startsWith('Location ('))
        ? rawAddress
        : CoordinateParser.formatOfflineGeotag(validLat, validLng);

    return LocationPoint(
      latitude: validLat,
      longitude: validLng,
      address: address,
      geohash: geohash,
    );
  }
}
