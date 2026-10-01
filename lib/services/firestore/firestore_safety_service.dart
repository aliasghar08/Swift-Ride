import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/safety_event_model.dart';
import '../../domain/models/safety_event_type.dart';

/// Service managing emergency SOS events and public trip share links in Firestore.
/// Matches composite index `safety_events (rideId ASC, createdAt DESC)`.
class FirestoreSafetyService {
  static final FirestoreSafetyService _instance = FirestoreSafetyService._internal();
  factory FirestoreSafetyService() => _instance;
  FirestoreSafetyService._internal();

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  final Map<String, SafetyEvent> _memoryEvents = {};
  final Map<String, Map<String, dynamic>> _memorySharedTrips = {};

  /// Records an emergency incident or telemetry anomaly in `safety_events/{eventId}`.
  Future<void> recordSafetyEvent(SafetyEvent event) async {
    _memoryEvents[event.id] = event;
    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.safetyEventsCollection).doc(event.id).set({
        'rideId': event.rideId,
        'type': event.type.name.toUpperCase(),
        'geopoint': GeoPoint(event.latitude, event.longitude),
        'metadata': event.metadata,
        'resolvedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreSafetyService] Error recording safety event: $e');
    }
  }

  /// Streams safety events for a specific ride.
  /// Utilizes composite index: `safety_events (rideId ASC, createdAt DESC)`.
  Stream<List<SafetyEvent>> streamEventsForRide(String rideId) {
    final fs = _firestore;
    if (fs == null) {
      final list = _memoryEvents.values.where((e) => e.rideId == rideId).toList();
      return Stream.value(list);
    }

    return fs
        .collection(AppConstants.safetyEventsCollection)
        .where('rideId', isEqualTo: rideId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((querySnap) {
      return querySnap.docs.map((doc) {
        final data = doc.data();
        final geo = data['geopoint'] as GeoPoint?;
        return SafetyEvent(
          id: doc.id,
          rideId: data['rideId'] ?? '',
          type: SafetyEventType.fromString(data['type'] ?? 'SOS'),
          latitude: geo?.latitude ?? 0.0,
          longitude: geo?.longitude ?? 0.0,
          metadata: (data['metadata'] as Map<String, dynamic>?) ?? {},
          createdAt: DateTime.now(),
        );
      }).toList();
    });
  }

  /// Creates a publicly readable trip document for "Share My Trip" web view.
  Future<void> createSharedTrip(String shareToken, Map<String, dynamic> tripData) async {
    _memorySharedTrips[shareToken] = tripData;
    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection('shared_trips').doc(shareToken).set({
        ...tripData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreSafetyService] Error creating shared trip: $e');
    }
  }

  /// Fetches a shared trip document by [shareToken].
  Future<Map<String, dynamic>?> getSharedTrip(String shareToken) async {
    final fs = _firestore;
    if (fs == null) {
      return _memorySharedTrips[shareToken];
    }

    try {
      final doc = await fs.collection('shared_trips').doc(shareToken).get();
      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      debugPrint('[FirestoreSafetyService] Error fetching shared trip: $e');
    }
    return _memorySharedTrips[shareToken];
  }

  /// Fetches all safety events for a ride once.
  Future<List<SafetyEvent>> getRideSafetyEvents(String rideId) async {
    final fs = _firestore;
    if (fs == null) {
      return _memoryEvents.values.where((e) => e.rideId == rideId).toList();
    }

    try {
      final snap = await fs
          .collection(AppConstants.safetyEventsCollection)
          .where('rideId', isEqualTo: rideId)
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs.map((doc) {
        final data = doc.data();
        final geo = data['geopoint'] as GeoPoint?;
        return SafetyEvent(
          id: doc.id,
          rideId: data['rideId'] ?? '',
          type: SafetyEventType.fromString(data['type'] ?? 'SOS'),
          latitude: geo?.latitude ?? 0.0,
          longitude: geo?.longitude ?? 0.0,
          metadata: (data['metadata'] as Map<String, dynamic>?) ?? {},
          createdAt: DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[FirestoreSafetyService] Error fetching safety events: $e');
      return _memoryEvents.values.where((e) => e.rideId == rideId).toList();
    }
  }

  /// Saves a shared trip public token linked to a ride ID.
  Future<void> saveSharedTripToken({
    required String token,
    required String rideId,
    required DateTime expiresAt,
  }) async {
    await createSharedTrip(token, {
      'token': token,
      'rideId': rideId,
      'expiresAt': expiresAt.toIso8601String(),
    });
  }

  /// Resolves a ride ID from a share token.
  Future<String?> getRideIdByShareToken(String token) async {
    final trip = await getSharedTrip(token);
    return trip?['rideId'] as String?;
  }
}

