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

  Map<String, dynamic> toMap() => {
        'geopoint': {'latitude': latitude, 'longitude': longitude},
        'address': address,
        'geohash': geohash,
      };

  factory LocationPoint.fromMap(Map<String, dynamic> map) {
    num? lat;
    num? lng;

    final geo = map['geopoint'];
    if (geo is Map) {
      lat = (geo['latitude'] ?? geo['lat']) as num?;
      lng = (geo['longitude'] ?? geo['lng']) as num?;
    } else if (geo != null) {
      // Handles cloud_firestore GeoPoint object dynamically without forcing compile-time dependency
      try {
        lat = (geo as dynamic).latitude as num?;
        lng = (geo as dynamic).longitude as num?;
      } catch (_) {}
    }

    lat ??= (map['latitude'] ?? map['lat']) as num?;
    lng ??= (map['longitude'] ?? map['lng']) as num?;

    // No silent fallback. A point without coordinates is corrupt, and
    // substituting a hardcoded city centre silently relocated real users to
    // Islamabad. Callers must handle this explicitly.
    if (lat == null || lng == null) {
      throw const FormatException('LocationPoint is missing coordinates');
    }

    return LocationPoint(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      address: map['address']?.toString() ?? '',
      geohash: map['geohash']?.toString() ?? '',
    );
  }
}
