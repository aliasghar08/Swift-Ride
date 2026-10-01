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

  Map<String, dynamic> toMap() => {
        'geopoint': {'latitude': latitude, 'longitude': longitude},
        'address': address,
        'geohash': geohash,
      };

  factory LocationPoint.fromMap(Map<String, dynamic> map) {
    final geo = map['geopoint'] as Map<String, dynamic>?;
    return LocationPoint(
      latitude: (geo?['latitude'] ?? map['latitude'] as num?)?.toDouble() ?? 37.7749,
      longitude: (geo?['longitude'] ?? map['longitude'] as num?)?.toDouble() ?? -122.4194,
      address: map['address'] ?? 'Selected Location',
      geohash: map['geohash'] ?? '',
    );
  }
}
