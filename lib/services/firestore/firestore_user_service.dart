import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/user_model.dart';
import '../../domain/models/user_role.dart';
import '../native/native_storage_service.dart';
import 'firestore_driver_service.dart';

/// Service managing user documents in Cloud Firestore (`users/{userId}`).
class FirestoreUserService {
  static final FirestoreUserService _instance = FirestoreUserService._internal();
  factory FirestoreUserService() => _instance;
  FirestoreUserService._internal() {
    unawaited(_hydratePhoneDirectory());
  }

  static const String _phoneDirectoryKey = 'registered_phone_profiles_v1';
  final NativeStorageService _storage = NativeStorageService();

  Future<void> _hydratePhoneDirectory() async {
    try {
      final raw = await _storage.getString(_phoneDirectoryKey);
      if (raw != null && raw.isNotEmpty) {
        _decodePhoneDirectory(raw);
      }
    } catch (_) {}
  }

  void _decodePhoneDirectory(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          final u = AppUser.fromMap(entry.value as Map<String, dynamic>);
          _phoneMemoryCache[entry.key] = u;
        }
      }
    } catch (_) {}
  }

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  // Memory fallback cache for testing environments and fast lookups
  final Map<String, AppUser> _memoryCache = {};
  final Map<String, AppUser> _phoneMemoryCache = {};

  String _phoneLookupKey(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    if (digits.length >= 9) {
      return digits.substring(digits.length - 9);
    }
    return digits;
  }

  void _indexUserInMemoryAndStorage(AppUser user) {
    var effectiveUser = user;
    if (user.id.isNotEmpty && _memoryCache.containsKey(user.id)) {
      final existing = _memoryCache[user.id]!;
      final finalPhone = (user.phone.isNotEmpty) ? user.phone : existing.phone;
      final mergedProviders = <String>{
        ...existing.linkedProviders,
        ...user.linkedProviders,
      }.toList();
      effectiveUser = user.copyWith(
        phone: finalPhone,
        linkedProviders: mergedProviders,
      );
    }

    if (effectiveUser.id.isNotEmpty) {
      _memoryCache[effectiveUser.id] = effectiveUser;
    }
    final key = _phoneLookupKey(effectiveUser.phone);
    if (key.length >= 9 &&
        effectiveUser.fullName.isNotEmpty &&
        effectiveUser.fullName != 'Guest User') {
      _phoneMemoryCache[key] = effectiveUser;
      if (key.length == 10) {
        _phoneMemoryCache[key.substring(1)] = effectiveUser;
      }
      _persistPhoneProfileEntry(key, effectiveUser);
    }
  }

  void _persistPhoneProfileEntry(String key, AppUser user) {
    try {
      final map = <String, dynamic>{};
      for (final entry in _phoneMemoryCache.entries) {
        map[entry.key] = entry.value.toMap();
      }
      map[key] = user.toMap();
      unawaited(_storage.setString(_phoneDirectoryKey, jsonEncode(map)));
    } catch (e) {
      debugPrint('[FirestoreUserService] Failed to persist phone directory: $e');
    }
  }

  Future<AppUser?> _readFromPersistentPhoneDirectory(String phone) async {
    final key = _phoneLookupKey(phone);
    if (key.length < 9) return null;

    if (_phoneMemoryCache.containsKey(key)) {
      return _phoneMemoryCache[key];
    }
    final tail9 = key.length >= 9 ? key.substring(key.length - 9) : key;
    if (_phoneMemoryCache.containsKey(tail9)) {
      return _phoneMemoryCache[tail9];
    }

    final syncRaw = _storage.peekStringSync(_phoneDirectoryKey);
    if (syncRaw != null && syncRaw.isNotEmpty) {
      _decodePhoneDirectory(syncRaw);
      if (_phoneMemoryCache.containsKey(key)) {
        return _phoneMemoryCache[key];
      }
      if (_phoneMemoryCache.containsKey(tail9)) {
        return _phoneMemoryCache[tail9];
      }
    }

    if (_firestore == null) {
      return null;
    }

    try {
      final raw = await _storage.getString(_phoneDirectoryKey);
      if (raw != null && raw.isNotEmpty) {
        _decodePhoneDirectory(raw);
        if (_phoneMemoryCache.containsKey(key)) {
          return _phoneMemoryCache[key];
        }
        if (_phoneMemoryCache.containsKey(tail9)) {
          return _phoneMemoryCache[tail9];
        }
      }
    } catch (e) {
      debugPrint('[FirestoreUserService] Error reading phone directory: $e');
    }
    return null;
  }

  /// Saves or creates a user document in Firestore and indexes by phone number.
  Future<void> saveUser(AppUser user) async {
    _indexUserInMemoryAndStorage(user);
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
          if (user.photoUrl != null) 'photoUrl': user.photoUrl,
          if (user.authProvider != null) 'authProvider': user.authProvider,
          if (user.linkedProviders.isNotEmpty) 'linkedProviders': user.linkedProviders,
          if (user.gender != null) 'gender': user.gender,
          'isGenderVerified': user.isGenderVerified,
        });
      } else {
        final existingData = docSnap.data();
        final existingPhone = existingData?['phone'] as String?;
        // Preserve existing non-empty phone during social profile updates
        final finalPhone = (user.phone.isNotEmpty)
            ? user.phone
            : (existingPhone ?? '');

        await docRef.update({
          'fullName': user.fullName,
          'phone': finalPhone,
          'email': user.email,
          'role': user.role.toDbString(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (user.photoUrl != null) 'photoUrl': user.photoUrl,
          if (user.authProvider != null) 'authProvider': user.authProvider,
          if (user.linkedProviders.isNotEmpty)
            'linkedProviders': FieldValue.arrayUnion(user.linkedProviders),
          if (user.gender != null) 'gender': user.gender,
          'isGenderVerified': user.isGenderVerified,
        });
      }

      // In future, any account with the driver role is automatically provisioned
      // in the root /drivers directory as well.
      if (user.role == UserRole.driver && user.id.isNotEmpty && !user.id.startsWith('guest')) {
        unawaited(FirestoreDriverService().ensureDriverProfileExists(
          userId: user.id,
          fullName: user.fullName,
          phone: user.phone,
          gender: user.gender,
          isGenderVerified: user.isGenderVerified,
        ));
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
        _indexUserInMemoryAndStorage(user);
        return user;
      }
    } catch (e) {
      debugPrint('[FirestoreUserService] Error fetching user $userId: $e');
    }
    return _memoryCache[userId];
  }

  /// Looks up an existing user profile by [phone] number across memory cache,
  /// persistent phone directory (`registered_phone_profiles_v1`), and Firestore.
  /// Supports formatted (`+923001234567`), local (`03001234567`), and raw digit variants.
  Future<AppUser?> getUserByPhone(String phone) async {
    final rawTrimmed = phone.trim();
    if (rawTrimmed.isEmpty) return null;

    final digits = rawTrimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;

    final normalized = AppUser.normalizePhone(rawTrimmed) ?? '+$digits';
    final candidates = <String>{
      rawTrimmed,
      normalized,
      '+$digits',
      digits,
    };
    if (digits.startsWith('92') && digits.length == 12) {
      candidates.add('0${digits.substring(2)}');
      candidates.add(digits.substring(2));
    } else if (digits.startsWith('0') && digits.length == 11) {
      candidates.add('+92${digits.substring(1)}');
      candidates.add('92${digits.substring(1)}');
    } else if (digits.length == 10 && digits.startsWith('3')) {
      candidates.add('+92$digits');
      candidates.add('0$digits');
    }

    // 1. Check in-memory cache first
    for (final user in _memoryCache.values) {
      final userDigits = user.phone.replaceAll(RegExp(r'\D'), '');
      if (candidates.contains(user.phone) ||
          (userDigits.isNotEmpty &&
              userDigits.length >= 9 &&
              digits.length >= 9 &&
              userDigits.substring(userDigits.length - 9) ==
                  digits.substring(digits.length - 9))) {
        return user;
      }
    }

    // 2. Check deterministic fallback user ID (`user_$digits`) in cache
    for (final candidate in candidates) {
      final clean = candidate.replaceAll(RegExp(r'\D'), '');
      final cachedById = _memoryCache['user_$clean'];
      if (cachedById != null) return cachedById;
    }

    // 3. Check persistent phone directory in NativeStorageService (survives signOut & restarts)
    final fromDirectory = await _readFromPersistentPhoneDirectory(normalized);
    if (fromDirectory != null) {
      _memoryCache[fromDirectory.id] = fromDirectory;
      return fromDirectory;
    }

    final fs = _firestore;
    if (fs == null) return null;

    // 4. Query Firestore `users` collection by phone candidates
    try {
      final queryList = candidates.take(10).toList();
      final snap = await fs
          .collection(AppConstants.usersCollection)
          .where('phone', whereIn: queryList)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        final user = AppUser.fromMap(doc.data(), docId: doc.id);
        _indexUserInMemoryAndStorage(user);
        return user;
      }

      // 5. Fallback: check deterministic document ID `user_$digits`
      final cleanNorm = normalized.replaceAll(RegExp(r'\D'), '');
      if (cleanNorm.isNotEmpty) {
        final fallbackDoc = await fs
            .collection(AppConstants.usersCollection)
            .doc('user_$cleanNorm')
            .get();
        if (fallbackDoc.exists && fallbackDoc.data() != null) {
          final user = AppUser.fromMap(fallbackDoc.data()!, docId: fallbackDoc.id);
          _indexUserInMemoryAndStorage(user);
          return user;
        }
      }
    } catch (e) {
      debugPrint('[FirestoreUserService] Error looking up user by phone $phone: $e');
    }

    return null;
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
      await fs.collection(AppConstants.usersCollection).doc(userId).set(
        {
          'trustedContacts': normalised,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

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

  /// Sets user gender ('female' | 'male') and optionally locks verification status.
  Future<bool> updateGender(String userId, String gender, {bool isVerified = false}) async {
    final cur = _memoryCache[userId];
    if (cur != null) {
      _memoryCache[userId] = cur.copyWith(
        gender: gender,
        isGenderVerified: isVerified,
      );
    }

    final fs = _firestore;
    if (fs == null) return true;

    try {
      await fs.collection(AppConstants.usersCollection).doc(userId).set(
        {
          'gender': gender,
          'isGenderVerified': isVerified,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      final cached = _memoryCache[userId];
      if (cached != null) {
        _memoryCache[userId] = cached.copyWith(
          gender: gender,
          isGenderVerified: isVerified,
        );
      }
      return true;
    } catch (e) {
      debugPrint('[FirestoreUserService] Error updating gender: $e');
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

  /// Permanently deletes user profile document and removes from memory cache and phone directory.
  Future<bool> deleteUser(String userId) async {
    final removed = _memoryCache.remove(userId);
    if (removed != null && removed.phone.isNotEmpty) {
      final key = _phoneLookupKey(removed.phone);
      _phoneMemoryCache.remove(key);
      if (key.length == 10) {
        _phoneMemoryCache.remove(key.substring(1));
      }
    }
    _phoneMemoryCache.removeWhere((_, u) => u.id == userId);
    try {
      final map = <String, dynamic>{};
      for (final entry in _phoneMemoryCache.entries) {
        map[entry.key] = entry.value.toMap();
      }
      unawaited(_storage.setString(_phoneDirectoryKey, jsonEncode(map)));
    } catch (_) {}

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

