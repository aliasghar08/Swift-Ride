import '../core/utils/id_generator.dart';
import '../domain/models/safety_event_model.dart';
import '../domain/models/safety_event_type.dart';

/// Zero-dependency safety service managing SOS alerts, live incident reports,
/// and public trip share tokens.
class SafetyService {
  /// Dispatches an emergency SOS incident with location telemetry.
  SafetyEvent createSosAlert({
    required String rideId,
    required String userId,
    required double latitude,
    required double longitude,
    required String message,
  }) {
    return SafetyEvent(
      id: IdGenerator.generateId(prefix: 'sos_'),
      rideId: rideId,
      type: SafetyEventType.sos,
      latitude: latitude,
      longitude: longitude,
      metadata: {
        'message': message,
        'triggeredBy': userId,
        'alertLevel': 'CRITICAL',
        'dispatchedAt': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
    );
  }

  /// Generates a secure random 12-character token for the public Share My Trip web view.
  String generateShareToken() {
    return IdGenerator.generateShareToken();
  }

  /// Records an automated safety anomaly (e.g. prolonged stop, route deviation).
  SafetyEvent recordSafetyIncident({
    required String rideId,
    required SafetyEventType type,
    required double latitude,
    required double longitude,
    required String details,
  }) {
    return SafetyEvent(
      id: IdGenerator.generateId(prefix: 'safe_'),
      rideId: rideId,
      type: type,
      latitude: latitude,
      longitude: longitude,
      metadata: {'details': details},
      createdAt: DateTime.now(),
    );
  }
}
