import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  /// Creates a server-side share token for [rideId] via the `shareTrip` Cloud
  /// Function, and returns the public tracking URL.
  ///
  /// Returns null when the token could not be created. Tokens MUST come from the
  /// server: `getSharedTrip` resolves them from the `shared_trips` collection, so
  /// a locally invented token produces a link that always reports as expired.
  Future<String?> createShareLink(String rideId) async {
    if (Firebase.apps.isEmpty) return null;

    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('shareTrip')
          .call(<String, dynamic>{'rideId': rideId});

      final data = res.data as Map<String, dynamic>;
      final token = data['shareToken'] as String?;
      if (token == null || token.isEmpty) return null;

      return (data['shareUrl'] as String?) ??
          'https://swiftride.app/track?token=$token';
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreSafetyService] shareTrip failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[FirestoreSafetyService] shareTrip failed: $e');
      return null;
    }
  }

  /// Honest outcome of an SOS dispatch attempt.
  ///
  /// [reachedAnyone] is false when no device could be notified — the UI must not
  /// claim help is coming in that case.
  Future<SosDispatchResult> triggerSos({
    required String rideId,
    required double latitude,
    required double longitude,
    String? message,
  }) async {
    if (Firebase.apps.isEmpty) {
      return const SosDispatchResult.failed(
        'SOS needs an internet connection to reach your contacts. Call local '
        'emergency services now.',
      );
    }

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('triggerSos').call(
        <String, dynamic>{
          'rideId': rideId,
          'location': {'latitude': latitude, 'longitude': longitude},
          'message': ?message,
        },
      );

      final data = res.data as Map<String, dynamic>;
      return SosDispatchResult(
        reachedAnyone: (data['reachedAnyone'] as bool?) ?? false,
        delivered: (data['delivered'] as num?)?.toInt() ?? 0,
        notifiedContacts: (data['notifiedContacts'] as num?)?.toInt() ?? 0,
        unreachablePhones:
            (data['unreachablePhones'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                const [],
        message: (data['emergencyNotice'] as String?) ??
            'Emergency alert recorded.',
        eventId: data['eventId'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreSafetyService] triggerSos failed: ${e.code} ${e.message}');
      return const SosDispatchResult.failed(
        'We could not reach the safety service. Call local emergency services now.',
      );
    } catch (e) {
      debugPrint('[FirestoreSafetyService] triggerSos failed: $e');
      return const SosDispatchResult.failed(
        'We could not send your emergency alert. Call local emergency services now.',
      );
    }
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
  /// Closes an open emergency alert.
  ///
  /// Returns null on success, or a message explaining the refusal. Nothing could
  /// resolve an alert before this, so once an SOS fired the assigned driver's
  /// banner never cleared.
  Future<String?> resolveSos(String eventId, {String? note}) async {
    if (Firebase.apps.isEmpty) {
      return 'Closing an alert needs an internet connection.';
    }

    try {
      await FirebaseFunctions.instance.httpsCallable('resolveSos').call(
        <String, dynamic>{
          'eventId': eventId,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreSafetyService] resolveSos: ${e.code} ${e.message}');
      return e.message ?? 'We could not close the alert.';
    } catch (e) {
      debugPrint('[FirestoreSafetyService] resolveSos failed: $e');
      return 'We could not close the alert.';
    }
  }

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



/// Outcome of an SOS dispatch, as reported by the `triggerSos` Cloud Function.
class SosDispatchResult {
  final bool reachedAnyone;
  final int delivered;
  final int notifiedContacts;
  final List<String> unreachablePhones;
  final String message;
  final String? eventId;

  const SosDispatchResult({
    required this.reachedAnyone,
    required this.delivered,
    required this.notifiedContacts,
    required this.unreachablePhones,
    required this.message,
    this.eventId,
  });

  const SosDispatchResult.failed(String reason)
      : reachedAnyone = false,
        delivered = 0,
        notifiedContacts = 0,
        unreachablePhones = const [],
        message = reason,
        eventId = null;
}
