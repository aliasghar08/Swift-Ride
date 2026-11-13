import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/user_model.dart';
import '../domain/models/user_role.dart';
import '../services/auth_service.dart';
import '../services/firestore/firestore_user_service.dart';
import '../services/native/native_storage_service.dart';

/// Production-ready Auth & Role Provider managing the active session with
/// Firebase Phone Authentication, Firestore user profile persistence, and NativeStorageService.
class AuthProvider extends ChangeNotifier {
  static const String _cachedProfileKey = 'cached_user_profile';

  final NativeStorageService _storage = NativeStorageService();
  final AuthService _authService = AuthService();
  final FirestoreUserService _firestoreUserService = FirestoreUserService();

  AppUser _currentUser;
  UserRole _activeRole;
  bool _isLoading = false;
  String? _authError;
  String? _verificationId;
  int? _resendToken;
  int _signOutGeneration = 0;
  StreamSubscription<User?>? _authSubscription;

  AuthProvider({
    AppUser? initialUser,
    UserRole initialRole = UserRole.rider,
  })  : _currentUser = initialUser ?? AppUser.guest(),
        _activeRole = initialRole {
    _loadPersistedRole();
    _initAuthListener();
    _initAnonymousSession();
  }

  Future<void> _initAnonymousSession() async {
    if (!_authService.isAuthenticated) {
      final cred = await _authService.signInAnonymously();
      if (cred?.user != null && _currentUser.id.isEmpty) {
        _currentUser = _currentUser.copyWith(id: cred!.user!.uid);
        _persistCurrentUser();
        notifyListeners();
      }
    }
  }

  Future<void> _persistCurrentUser() async {
    try {
      if (_currentUser.phone.isNotEmpty ||
          (_currentUser.id.isNotEmpty && !_currentUser.id.startsWith('guest'))) {
        await _storage.setString(_cachedProfileKey, jsonEncode(_currentUser.toMap()));
      }
    } catch (e) {
      debugPrint('[AuthProvider] Failed to persist user profile: $e');
    }
  }

  AppUser get currentUser => _currentUser;
  UserRole get activeRole => _activeRole;
  bool get isLoading => _isLoading;
  String? get authError => _authError;
  String? get verificationId => _verificationId;
  int? get resendToken => _resendToken;
  int get signOutGeneration => _signOutGeneration;
  bool get isAuthenticated =>
      _authService.isAuthenticated ||
      _currentUser.phone.isNotEmpty ||
      (_currentUser.id.isNotEmpty && !_currentUser.id.startsWith('guest'));

  AuthService get authService => _authService;
  FirestoreUserService get firestoreUserService => _firestoreUserService;

  Future<void> _loadPersistedRole() async {
    // 1. Restore cached user profile to instantly remember the signed-in session
    try {
      final profileJson = await _storage.getString(_cachedProfileKey);
      if (profileJson != null && profileJson.isNotEmpty) {
        final map = jsonDecode(profileJson) as Map<String, dynamic>;
        final restored = AppUser.fromMap(map);
        if (restored.phone.isNotEmpty ||
            (restored.id.isNotEmpty && !restored.id.startsWith('guest'))) {
          _currentUser = restored;
          _activeRole = restored.role;
          unawaited(_firestoreUserService.saveUser(restored));
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[AuthProvider] Error restoring cached user profile: $e');
    }

    // 2. Restore active role selection
    final roleStr = await _storage.getString('active_user_role');
    if (roleStr != null) {
      if (roleStr == 'driver' && _activeRole != UserRole.driver) {
        _activeRole = UserRole.driver;
        notifyListeners();
      } else if (roleStr == 'admin' && _activeRole != UserRole.admin) {
        if (_currentUser.role == UserRole.admin) {
          _activeRole = UserRole.admin;
          notifyListeners();
        } else {
          _activeRole = UserRole.rider;
          _storage.setString('active_user_role', 'rider');
          notifyListeners();
        }
      } else if (roleStr == 'rider' && _activeRole != UserRole.rider) {
        _activeRole = UserRole.rider;
        notifyListeners();
      }
    }
  }

  void _initAuthListener() {
    _authSubscription = _authService.authStateChanges.listen((user) async {
      if (user != null &&
          (!user.isAnonymous ||
              (user.phoneNumber != null && user.phoneNumber!.isNotEmpty))) {
        try {
          final profile = await _firestoreUserService.getUser(user.uid);
          if (profile != null &&
              (profile.phone.isNotEmpty ||
                  (profile.id.isNotEmpty && !profile.id.startsWith('guest')))) {
            _currentUser = profile;
            _activeRole = profile.role;
            _persistCurrentUser();
            notifyListeners();
          } else if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
            _currentUser = _currentUser.copyWith(
              id: user.uid,
              phone: user.phoneNumber,
            );
            _persistCurrentUser();
            notifyListeners();
          } else if (user.email != null && user.email!.isNotEmpty) {
            _currentUser = _currentUser.copyWith(
              id: user.uid,
              email: user.email,
              fullName: user.displayName ?? _currentUser.fullName,
              photoUrl: user.photoURL,
            );
            _persistCurrentUser();
            notifyListeners();
          }
        } catch (e) {
          debugPrint('[AuthProvider] Error loading user profile on auth change: $e');
        }
      }
    });
  }

  /// Sends an SMS OTP code to [phoneNumber].
  Future<void> sendOtp({
    required String phoneNumber,
    void Function(String verificationId, int? resendToken)? onCodeSent,
    void Function(String error)? onError,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
    void Function(String verificationId)? onAutoRetrievalTimeout,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    await _authService.sendOtp(
      phoneNumber: phoneNumber,
      forceResendingToken: _resendToken,
      onCodeSent: (vId, token) {
        _verificationId = vId;
        _resendToken = token;
        _isLoading = false;
        notifyListeners();
        onCodeSent?.call(vId, token);
      },
      onError: (errMsg) {
        _authError = errMsg;
        _isLoading = false;
        notifyListeners();
        onError?.call(errMsg);
      },
      onAutoVerified: (credential) async {
        _isLoading = false;
        notifyListeners();
        onAutoVerified?.call(credential);
      },
      onAutoRetrievalTimeout: (vId) {
        onAutoRetrievalTimeout?.call(vId);
      },
    );
  }

  /// Signs in directly with a [PhoneAuthCredential] from auto-retrieval and updates the profile.
  Future<UserCredential?> signInWithCredential(
    PhoneAuthCredential credential, {
    String? phoneNumber,
    String? fullName,
    String? email,
    UserRole? role,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final userCred = await _authService.signInWithCredential(credential);
      final phone = phoneNumber ?? userCred?.user?.phoneNumber ?? '';
      final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final uid = userCred?.user?.uid ??
          'user_${cleanDigits.isNotEmpty ? cleanDigits : DateTime.now().millisecondsSinceEpoch}';

      final resolvedRole = role ?? _activeRole;
      final resolvedEmail = (email != null && email.trim().isNotEmpty)
          ? email.trim()
          : _currentUser.email;
      final updatedUser = await _authService.syncUserProfile(
        uid: uid,
        phone: phone,
        fullName: (fullName != null && fullName.trim().isNotEmpty)
            ? fullName.trim()
            : (_currentUser.fullName.isNotEmpty && _currentUser.fullName != 'Guest User'
                ? _currentUser.fullName
                : 'SwiftRide User'),
        email: resolvedEmail,
        defaultRole: resolvedRole,
      );

      _currentUser = updatedUser;
      _activeRole = updatedUser.role;
      _storage.setString('active_user_role', _activeRole.name);
      _persistCurrentUser();
      _isLoading = false;
      notifyListeners();
      return userCred;
    } catch (e) {
      _isLoading = false;
      final errMsg = e is FirebaseAuthException ? (e.message ?? e.code) : e.toString();
      _authError = errMsg;
      notifyListeners();
      rethrow;
    }
  }

  /// Verifies entered OTP [smsCode] against active verification ID and signs in.
  Future<bool> verifyOtp({
    required String smsCode,
    required String phoneNumber,
    String? fullName,
    String? email,
    UserRole? role,
    void Function()? onSuccess,
    void Function(String error)? onError,
  }) async {
    final vId = _verificationId;
    if (vId == null && _authService.isAuthenticated == false) {
      const err = 'No active verification ID found. Please request an OTP first.';
      _authError = err;
      notifyListeners();
      onError?.call(err);
      return false;
    }

    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final credential = await _authService.verifyOtpAndSignIn(
        verificationId: vId ?? '',
        smsCode: smsCode,
      );

      // Resolve valid UID from credential, active session, or phone identity
      final cleanDigits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      final fallbackUid = cleanDigits.isNotEmpty
          ? 'user_$cleanDigits'
          : 'user_${DateTime.now().millisecondsSinceEpoch}';

      final uid = credential?.user?.uid ??
          _authService.currentUser?.uid ??
          fallbackUid;

      final resolvedRole = role ?? _activeRole;
      final resolvedEmail = (email != null && email.trim().isNotEmpty)
          ? email.trim()
          : _currentUser.email;

      final updatedUser = await _authService.syncUserProfile(
        uid: uid,
        phone: phoneNumber,
        fullName: (fullName != null && fullName.trim().isNotEmpty)
            ? fullName.trim()
            : (_currentUser.fullName.isNotEmpty && _currentUser.fullName != 'Guest User'
                ? _currentUser.fullName
                : 'SwiftRide User'),
        email: resolvedEmail,
        defaultRole: resolvedRole,
      );

      _currentUser = updatedUser;
      _activeRole = updatedUser.role;
      _storage.setString('active_user_role', _activeRole.name);
      _persistCurrentUser();
      _isLoading = false;
      notifyListeners();
      onSuccess?.call();
      return true;
    } catch (e) {
      _isLoading = false;
      final errMsg = e is FirebaseAuthException ? (e.message ?? e.code) : e.toString();
      _authError = errMsg;
      notifyListeners();
      onError?.call(errMsg);
      return false;
    }
  }

  /// Authenticates using Google Sign-In and persists user profile.
  Future<bool> signInWithGoogle({
    required String selectedRole,
    String? fullName,
    void Function()? onSuccess,
    void Function(String error)? onError,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle(
        selectedRole: selectedRole,
        fullName: fullName,
      );

      if (user == null) {
        // User cancelled flow without error
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _currentUser = user;
      _activeRole = user.role;
      _storage.setString('active_user_role', _activeRole.name);
      _persistCurrentUser();
      _isLoading = false;
      notifyListeners();
      onSuccess?.call();
      return true;
    } catch (e) {
      _isLoading = false;
      final errMsg = e is FirebaseAuthException ? (e.message ?? e.code) : e.toString();
      _authError = errMsg;
      notifyListeners();
      onError?.call(errMsg);
      return false;
    }
  }

  /// Authenticates using Apple Sign-In and persists user profile.
  Future<bool> signInWithApple({
    required String selectedRole,
    String? fullName,
    void Function()? onSuccess,
    void Function(String error)? onError,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithApple(
        selectedRole: selectedRole,
        fullName: fullName,
      );

      if (user == null) {
        // User cancelled flow without error
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _currentUser = user;
      _activeRole = user.role;
      _storage.setString('active_user_role', _activeRole.name);
      _persistCurrentUser();
      _isLoading = false;
      notifyListeners();
      onSuccess?.call();
      return true;
    } catch (e) {
      _isLoading = false;
      final errMsg = e is FirebaseAuthException ? (e.message ?? e.code) : e.toString();
      _authError = errMsg;
      notifyListeners();
      onError?.call(errMsg);
      return false;
    }
  }

  /// Automatically looks up user profile info by [phoneNumber] from local cache or Firestore
  /// so the login/signup form can autofill Name, Email, and Role while keeping them editable.
  Future<AppUser?> lookupUserByPhone(String phoneNumber) async {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return null;

    final tail = digits.substring(digits.length - 9);

    // 1. Check current user in memory
    final currentDigits = _currentUser.phone.replaceAll(RegExp(r'\D'), '');
    if (currentDigits.length >= 9 &&
        currentDigits.substring(currentDigits.length - 9) == tail &&
        _currentUser.fullName.isNotEmpty &&
        _currentUser.fullName != 'Guest User') {
      return _currentUser;
    }

    // 2. Query FirestoreUserService (memory cache + Firestore `users` collection)
    final fromFirestore = await _firestoreUserService.getUserByPhone(phoneNumber);
    if (fromFirestore != null) {
      return fromFirestore;
    }

    // 3. Fallback: check cached profile in NativeStorageService
    try {
      final profileJson = _storage.peekStringSync(_cachedProfileKey);
      if (profileJson != null && profileJson.isNotEmpty) {
        final map = jsonDecode(profileJson) as Map<String, dynamic>;
        final cachedUser = AppUser.fromMap(map);
        final cachedDigits = cachedUser.phone.replaceAll(RegExp(r'\D'), '');
        if (cachedDigits.length >= 9 &&
            cachedDigits.substring(cachedDigits.length - 9) == tail &&
            cachedUser.fullName.isNotEmpty &&
            cachedUser.fullName != 'Guest User') {
          return cachedUser;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Sign out the current user session while remembering registered phone profiles.
  Future<void> signOut() async {
    _isLoading = true;
    _authError = null;
    notifyListeners();
    try {
      // Ensure any profile edits made during the session are indexed by phone before signing out
      if (_currentUser.phone.isNotEmpty &&
          _currentUser.fullName.isNotEmpty &&
          _currentUser.fullName != 'Guest User') {
        await _firestoreUserService.saveUser(_currentUser);
      }
      await _authService.signOut();
      unawaited(_storage.remove(_cachedProfileKey));
      _verificationId = null;
      _resendToken = null;
      _currentUser = AppUser(
        id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
        fullName: 'Guest User',
        phone: '',
        role: UserRole.rider,
        rating: 5.0,
        totalRides: 0,
        createdAt: DateTime.now(),
      );
      _activeRole = UserRole.rider;
      _signOutGeneration++;
      unawaited(_storage.setString('active_user_role', 'rider'));
      unawaited(_initAnonymousSession());
    } catch (e) {
      _authError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Permanently deletes the active user profile and credentials,
  /// resetting the session cleanly to guest state.
  /// Complies with Apple App Store Review Guideline 5.1.1(v).
  Future<bool> deleteAccount() async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      if (_currentUser.id.isNotEmpty) {
        await _firestoreUserService.deleteUser(_currentUser.id);
      }
      await _authService.deleteAccount();
      unawaited(_storage.remove(_cachedProfileKey));
      _verificationId = null;
      _resendToken = null;
      _currentUser = AppUser(
        id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
        fullName: 'Guest User',
        phone: '',
        role: UserRole.rider,
        rating: 5.0,
        totalRides: 0,
        createdAt: DateTime.now(),
      );
      _activeRole = UserRole.rider;
      _signOutGeneration++;
      unawaited(_storage.setString('active_user_role', 'rider'));
      unawaited(_storage.remove('driver_daily_khata'));
      unawaited(_initAnonymousSession());
      return true;
    } catch (e) {
      final errMsg = e is FirebaseAuthException ? (e.message ?? e.code) : e.toString();
      _authError = errMsg;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _authError = null;
    notifyListeners();
  }

  void setVerificationId(String id, int? token) {
    _verificationId = id;
    _resendToken = token;
    notifyListeners();
  }

  void switchRole(UserRole role) {
    if (_activeRole == role && _currentUser.role == role) return;
    _activeRole = role;
    _currentUser = _currentUser.copyWith(role: role);
    _storage.setString('active_user_role', role.name);
    _persistCurrentUser();
    notifyListeners();

    // Sync role to Firestore if user ID exists
    if (_currentUser.id.isNotEmpty) {
      _firestoreUserService.saveUser(_currentUser).catchError((e) {
        debugPrint('[AuthProvider] Failed to sync role to Firestore: $e');
      });
    }
  }

  void updateUser(AppUser user) {
    _currentUser = user;
    _persistCurrentUser();
    notifyListeners();
  }

  Future<void> updateFullName(String fullName) async {
    await updateUserProfile(fullName: fullName);
  }

  /// Updates user profile fields (name, phone, optional email, and role) across
  /// in-memory state, native storage cache, and Cloud Firestore.
  Future<void> updateUserProfile({
    String? fullName,
    String? phone,
    String? email,
    UserRole? role,
  }) async {
    final nextName = (fullName != null && fullName.trim().isNotEmpty)
        ? fullName.trim()
        : _currentUser.fullName;
    final nextPhone = (phone != null && phone.trim().isNotEmpty)
        ? (AppUser.normalizePhone(phone.trim()) ?? phone.trim())
        : _currentUser.phone;
    final nextEmail = email != null
        ? (email.trim().isEmpty ? null : email.trim())
        : _currentUser.email;
    final nextRole = role ?? _currentUser.role;

    _currentUser = AppUser(
      id: _currentUser.id.isNotEmpty
          ? _currentUser.id
          : 'user_${nextPhone.replaceAll(RegExp(r'\D'), '')}',
      fullName: nextName,
      phone: nextPhone,
      email: nextEmail,
      role: nextRole,
      rating: _currentUser.rating,
      totalRides: _currentUser.totalRides,
      fcmTokens: _currentUser.fcmTokens,
      trustedContacts: _currentUser.trustedContacts,
      createdAt: _currentUser.createdAt,
    );
    if (role != null) {
      _activeRole = role;
      _storage.setString('active_user_role', role.name);
    }
    _persistCurrentUser();
    try {
      await _firestoreUserService.saveUser(_currentUser);
    } catch (e) {
      debugPrint('[AuthProvider] Failed to save updated user profile to Firestore: $e');
    }
    notifyListeners();
  }

  void incrementRidesCount() {
    _currentUser = _currentUser.copyWith(totalRides: _currentUser.totalRides + 1);
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
