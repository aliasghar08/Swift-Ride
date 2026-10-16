import 'dart:async';
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
  final NativeStorageService _storage = NativeStorageService();
  final AuthService _authService = AuthService();
  final FirestoreUserService _firestoreUserService = FirestoreUserService();

  AppUser _currentUser;
  UserRole _activeRole;
  bool _isLoading = false;
  String? _authError;
  String? _verificationId;
  int? _resendToken;
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
      await _authService.signInAnonymously();
    }
  }

  AppUser get currentUser => _currentUser;
  UserRole get activeRole => _activeRole;
  bool get isLoading => _isLoading;
  String? get authError => _authError;
  String? get verificationId => _verificationId;
  int? get resendToken => _resendToken;
  bool get isAuthenticated => _authService.isAuthenticated;

  AuthService get authService => _authService;
  FirestoreUserService get firestoreUserService => _firestoreUserService;

  Future<void> _loadPersistedRole() async {
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
      if (user != null) {
        try {
          final profile = await _firestoreUserService.getUser(user.uid);
          if (profile != null) {
            _currentUser = profile;
            _activeRole = profile.role;
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
      },
    );
  }

  /// Verifies entered OTP [smsCode] against active verification ID and signs in.
  Future<bool> verifyOtp({
    required String smsCode,
    required String phoneNumber,
    String? fullName,
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
        verificationId: vId ?? 'mock_verification_id',
        smsCode: smsCode,
      );

      // Never invent an identity. If Firebase did not return a real user we must
      // fail closed: a fabricated uid would mint a fake authenticated session
      // (and, before this fix, did so in release builds too).
      final uid = credential?.user?.uid ??
          _authService.currentUser?.uid ??
          (kDebugMode ? 'debug_user_${DateTime.now().millisecondsSinceEpoch}' : null);
      if (uid == null) {
        _isLoading = false;
        const msg = 'We could not sign you in. Please request a new code and try again.';
        _authError = msg;
        notifyListeners();
        onError?.call(msg);
        return false;
      }

      final resolvedRole = role ?? _activeRole;

      final updatedUser = await _authService.syncUserProfile(
        uid: uid,
        phone: phoneNumber,
        fullName: fullName ?? _currentUser.fullName,
        defaultRole: resolvedRole,
      );

      _currentUser = updatedUser;
      _activeRole = updatedUser.role;
      _storage.setString('active_user_role', _activeRole.name);
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

  /// Sign out the current user session.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signOut();
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
      await _storage.setString('active_user_role', 'rider');
    } catch (e) {
      _authError = e.toString();
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
    if (_activeRole == role) return;
    _activeRole = role;
    _storage.setString('active_user_role', role.name);
    notifyListeners();
  }

  void updateUser(AppUser user) {
    _currentUser = user;
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
