import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/user_model.dart';

/// Service managing user documents in Cloud Firestore (`users/{userId}`).
class FirestoreUserService {
  static final FirestoreUserService _instance = FirestoreUserService._internal();
  factory FirestoreUserService() => _instance;
  FirestoreUserService._internal();

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  // Memory fallback cache for testing environments
  final Map<String, AppUser> _memoryCache = {};

  /// Saves or creates a user document in Firestore.
  Future<void> saveUser(AppUser user) async {
    _memoryCache[user.id] = user;
    final fs = _firestore;
    if (fs == null) return;

    try {
      final docRef = fs.collection(AppConstants.usersCollection).doc(user.id);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        await docRef.set({
          'phone': user.phone,
          'email': user.email,
          'fullName': user.fullName,
          'role': user.role.toDbString(),
          'rating': user.rating,
          'totalRides': user.totalRides,
          'fcmTokens': user.fcmTokens,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'location': null,
        });
      } else {
        await docRef.update({
          'fullName': user.fullName,
          'phone': user.phone,
          'email': user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[FirestoreUserService] Error saving user ${user.id}: $e');
    }
  }

  /// Fetches user profile document by [userId].
  Future<AppUser?> getUser(String userId) async {
    final fs = _firestore;
    if (fs == null) {
      return _memoryCache[userId];
    }

    try {
      final doc = await fs.collection(AppConstants.usersCollection).doc(userId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final user = AppUser.fromMap(data, docId: doc.id);
        _memoryCache[userId] = user;
        return user;
      }
    } catch (e) {
      debugPrint('[FirestoreUserService] Error fetching user $userId: $e');
    }
    return _memoryCache[userId];
  }

  /// Real-time stream of user profile changes.
  Stream<AppUser?> streamUser(String userId) {
    final fs = _firestore;
    if (fs == null) {
      return Stream.value(_memoryCache[userId]);
    }

    return fs.collection(AppConstants.usersCollection).doc(userId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      final user = AppUser.fromMap(snapshot.data()!, docId: snapshot.id);
      _memoryCache[userId] = user;
      return user;
    });
  }

  /// Appends an FCM token to user's device list.
  Future<void> addFcmToken(String userId, String token) async {
    final fs = _firestore;
    if (fs == null) {
      final user = _memoryCache[userId];
      if (user != null && !user.fcmTokens.contains(token)) {
        _memoryCache[userId] = user.copyWith(fcmTokens: [...user.fcmTokens, token]);
      }
      return;
    }

    try {
      await fs.collection(AppConstants.usersCollection).doc(userId).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreUserService] Error adding FCM token: $e');
    }
  }

  /// Replaces this user's trusted-contact phone numbers.
  ///
  /// Returns false when the write failed, so the UI does not tell someone their
  /// emergency contacts were saved when they were not.
  Future<bool> updateTrustedContacts(String userId, List<String> phones) async {
    final normalised = phones
        .map(AppUser.normalizePhone)
        .whereType<String>()
        .toSet()
        .toList();

    final fs = _firestore;
    if (fs == null) {
      final user = _memoryCache[userId];
      if (user != null) {
        _memoryCache[userId] = user.copyWith(trustedContacts: normalised);
      }
      return true;
    }

    try {
      await fs.collection(AppConstants.usersCollection).doc(userId).update({
        'trustedContacts': normalised,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final cached = _memoryCache[userId];
      if (cached != null) {
        _memoryCache[userId] = cached.copyWith(trustedContacts: normalised);
      }
      return true;
    } catch (e) {
      debugPrint('[FirestoreUserService] Error updating trusted contacts: $e');
      return false;
    }
  }

  /// Convenience alias for addFcmToken
  Future<void> updateFcmToken(String userId, String token) => addFcmToken(userId, token);

  /// Removes a device token, e.g. when the user signs out.
  ///
  /// Without this a signed-out device keeps receiving the previous account's
  /// emergency alerts.
  Future<void> removeFcmToken(String userId, String token) async {
    final fs = _firestore;
    if (fs == null) {
      final user = _memoryCache[userId];
      if (user != null) {
        _memoryCache[userId] = user.copyWith(
          fcmTokens: user.fcmTokens.where((t) => t != token).toList(),
        );
      }
      return;
    }

    try {
      await fs.collection(AppConstants.usersCollection).doc(userId).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final cached = _memoryCache[userId];
      if (cached != null) {
        _memoryCache[userId] = cached.copyWith(
          fcmTokens: cached.fcmTokens.where((t) => t != token).toList(),
        );
      }
    } catch (e) {
      debugPrint('[FirestoreUserService] Error removing FCM token: $e');
    }
  }

  /// Reads a user's registered device tokens (used by tests and diagnostics).
  Future<List<String>> fcmTokensFor(String userId) async {
    final user = await getUser(userId);
    return user?.fcmTokens ?? const [];
  }


  /// Updates user's real-time geographic location coordinates.
  Future<void> updateLocation(String userId, double lat, double lng) async {
    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.usersCollection).doc(userId).update({
        'location': {
          'geopoint': GeoPoint(lat, lng),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      debugPrint('[FirestoreUserService] Error updating location: $e');
    }
  }

  /// Permanently deletes user profile document and removes from memory cache.
  Future<bool> deleteUser(String userId) async {
    _memoryCache.remove(userId);
    final fs = _firestore;
    if (fs == null) return true;

    try {
      await fs.collection(AppConstants.usersCollection).doc(userId).delete();
      debugPrint('[FirestoreUserService] Successfully deleted Firestore user $userId');
      return true;
    } catch (e) {
      debugPrint('[FirestoreUserService] Error deleting user $userId: $e');
      return false;
    }
  }
}

