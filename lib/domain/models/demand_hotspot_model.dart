import 'dart:math' as math;

/// Represents a live geographic demand cluster computed by Cloud Functions analytics.
class DemandHotspot {
  final String cellId;
  final double lat;
  final double lng;
  final double demandScore;
  final double surgeMultiplier;
  final int requestCount;
  final int driverCount;
  final double radiusM;
  final DateTime updatedAt;
  final DateTime expiresAt;

  const DemandHotspot({
    required this.cellId,
    required this.lat,
    required this.lng,
    required this.demandScore,
    this.surgeMultiplier = 1.0,
    this.requestCount = 0,
    this.driverCount = 0,
    this.radiusM = 650.0,
    required this.updatedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isHighDemand => demandScore >= 0.70;
  bool get isModerateDemand => demandScore >= 0.40 && demandScore < 0.70;

  /// Haversine distance in kilometers from a coordinate to this hotspot centroid.
  double distanceToKm(double fromLat, double fromLng) {
    const double earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat - fromLat);
    final dLng = _deg2rad(lng - fromLng);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(fromLat)) *
            math.cos(_deg2rad(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);

  Map<String, dynamic> toMap() => {
        'cellId': cellId,
        'lat': lat,
        'lng': lng,
        'demandScore': demandScore,
        'surgeMultiplier': surgeMultiplier,
        'requestCount': requestCount,
        'driverCount': driverCount,
        'radiusM': radiusM,
        'updatedAt': updatedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory DemandHotspot.fromMap(Map<String, dynamic> map, {String? docId}) {
    final cellId = docId ?? map['cellId']?.toString() ?? '';
    final lat = (map['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (map['lng'] as num?)?.toDouble() ?? 0.0;
    final demandScore = (map['demandScore'] as num?)?.toDouble() ?? 0.0;
    final surgeMultiplier = (map['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
    final requestCount = (map['requestCount'] as num?)?.toInt() ?? 0;
    final driverCount = (map['driverCount'] as num?)?.toInt() ?? 0;
    final radiusM = (map['radiusM'] as num?)?.toDouble() ?? 650.0;

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      try {
        final dt = (v as dynamic).toDate();
        if (dt is DateTime) return dt;
      } catch (_) {}
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return DemandHotspot(
      cellId: cellId,
      lat: lat,
      lng: lng,
      demandScore: demandScore,
      surgeMultiplier: surgeMultiplier,
      requestCount: requestCount,
      driverCount: driverCount,
      radiusM: radiusM,
      updatedAt: parseDate(map['updatedAt']),
      expiresAt: parseDate(map['expiresAt']),
    );
  }
}
