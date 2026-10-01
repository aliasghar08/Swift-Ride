import 'package:flutter/foundation.dart';
import '../domain/models/safety_event_model.dart';
import '../domain/models/safety_event_type.dart';
import '../services/safety_service.dart';

/// Zero-dependency Safety Provider managing real-time SOS dispatches,
/// automated hazard/deviation flags, and secure trip sharing links.
class SafetyProvider extends ChangeNotifier {
  final SafetyService _safetyService;
  List<SafetyEvent> _safetyEvents = [];

  SafetyProvider({
    SafetyService? safetyService,
    List<SafetyEvent>? initialEvents,
  })  : _safetyService = safetyService ?? SafetyService(),
        _safetyEvents = initialEvents ?? [];

  List<SafetyEvent> get safetyEvents => List.unmodifiable(_safetyEvents);

  /// Dispatches an emergency SOS signal with current coordinates.
  SafetyEvent triggerSos({
    String rideId = 'active_ride',
    String userId = 'user_current',
    double latitude = 37.7749,
    double longitude = -122.4194,
    String message = 'Emergency assistance requested via SwiftRide SOS button',
  }) {
    final event = _safetyService.createSosAlert(
      rideId: rideId,
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      message: message,
    );

    _safetyEvents = [event, ..._safetyEvents];
    notifyListeners();
    return event;
  }

  /// Generates a unique 12-char web token for live public trip tracking.
  String generateShareToken() {
    return _safetyService.generateShareToken();
  }

  /// Records an automated anomaly (route deviation, sudden deceleration).
  void recordAnomaly({
    required String rideId,
    required SafetyEventType type,
    required double latitude,
    required double longitude,
    required String details,
  }) {
    final event = _safetyService.recordSafetyIncident(
      rideId: rideId,
      type: type,
      latitude: latitude,
      longitude: longitude,
      details: details,
    );

    _safetyEvents = [event, ..._safetyEvents];
    notifyListeners();
  }
}
