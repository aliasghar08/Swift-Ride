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
    final geo = map['geopoint'] as Map<String, dynamic>?;
    final lat = (geo?['latitude'] ?? map['latitude']) as num?;
    final lng = (geo?['longitude'] ?? map['longitude']) as num?;

    // No silent fallback. A point without coordinates is corrupt, and
    // substituting a hardcoded city centre silently relocated real users to
    // Islamabad. Callers must handle this explicitly.
    if (lat == null || lng == null) {
      throw const FormatException('LocationPoint is missing coordinates');
    }

    return LocationPoint(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      address: map['address'] ?? '',
      geohash: map['geohash'] ?? '',
    );
  }
}
