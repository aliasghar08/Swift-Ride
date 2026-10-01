import 'safety_event_type.dart';

class SafetyEvent {
  final String id;
  final String rideId;
  final SafetyEventType type;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> metadata;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  const SafetyEvent({
    required this.id,
    required this.rideId,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.metadata = const {},
    this.resolvedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'rideId': rideId,
        'type': type.toDbString(),
        'geopoint': {'latitude': latitude, 'longitude': longitude},
        'metadata': metadata,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory SafetyEvent.fromMap(Map<String, dynamic> map, {String? docId}) {
    final geo = map['geopoint'] as Map<String, dynamic>?;
    return SafetyEvent(
      id: docId ?? map['id'] ?? '',
      rideId: map['rideId'] ?? '',
      type: SafetyEventType.fromString(map['type']),
      latitude: (geo?['latitude'] as num?)?.toDouble() ?? 37.7749,
      longitude: (geo?['longitude'] as num?)?.toDouble() ?? -122.4194,
      metadata: map['metadata'] as Map<String, dynamic>? ?? {},
      resolvedAt: map['resolvedAt'] != null
          ? DateTime.tryParse(map['resolvedAt'].toString())
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
