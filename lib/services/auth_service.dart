import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/user_model.dart';
import '../domain/models/user_role.dart';
import 'firestore/firestore_user_service.dart';

/// Production-ready Firebase Phone Authentication service.
/// Supports OTP verification, auto-retrieval, resend token management,
/// and graceful fallback for uninitialized Firebase environments (e.g. unit/widget tests).
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  FirebaseAuth? get _auth {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance;
      }
    } catch (_) {}
    return null;
  }

  final FirestoreUserService _userService = FirestoreUserService();

  /// Stream of authentication state changes.
  Stream<User?> get authStateChanges {
    final auth = _auth;
    if (auth != null) {
      return auth.authStateChanges();
    }
    return Stream.value(null);
  }

  /// Current signed-in Firebase user (or null).
  User? get currentFirebaseUser => _auth?.currentUser;

  /// Whether a real Firebase user is currently authenticated.
  bool get isAuthenticated => currentFirebaseUser != null;

  /// Signs in anonymously so unauthenticated guests can mint valid tokens
  /// for Cloud Functions callables (maps, routes, fare estimates).
  Future<UserCredential?> signInAnonymously() async {
    final auth = _auth;
    if (auth == null) return null;
    try {
      if (auth.currentUser != null) {
        return null;
      }
      debugPrint('[AuthService] Initiating anonymous sign-in...');
      final cred = await auth.signInAnonymously();
      debugPrint('[AuthService] Anonymous sign-in success: ${cred.user?.uid}');
      return cred;
    } catch (e) {
      debugPrint('[AuthService] Anonymous sign-in failed: $e');
      return null;
    }
  }

  /// Dispatches an SMS verification code to [phoneNumber].
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String errorMessage) onError,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final auth = _auth;
    if (auth == null) {
      // Firebase is genuinely unavailable. Only a debug build may simulate an OTP;
      // a release build must fail loudly instead of pretending an SMS was sent.
      if (!kDebugMode) {
        const msg =
            'Sign-in is unavailable right now. Please check your connection and try again.';
        debugPrint('[AuthService] sendOtp aborted (Firebase unavailable)');
        onError(msg);
        return;
      }
      debugPrint('[AuthService] Firebase unavailable: simulating OTP (debug build only)');
      await Future.delayed(const Duration(milliseconds: 300));
      onCodeSent('mock_verification_id_${DateTime.now().millisecondsSinceEpoch}', 123456);
      return;
    }

    try {
      await auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: timeout,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('[AuthService] Auto-verification completed on device');
          try {
            await auth.signInWithCredential(credential);
            onAutoVerified?.call(credential);
          } catch (e) {
            onError(e.toString());
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('[AuthService] Phone verification failed: ${e.code} - ${e.message}');
          String message = 'Phone verification failed. Please try again.';
          if (e.code == 'invalid-phone-number') {
            message = 'The phone number format is invalid. Please use international format (e.g. +923001234567).';
          } else if (e.code == 'too-many-requests') {
            message = 'Too many requests sent. Please wait a few moments before trying again.';
          } else if (e.code == 'quota-exceeded') {
            message = 'SMS quota exceeded for today. Please contact support or use a test phone number.';
          }
          onError(message);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('[AuthService] OTP code sent successfully. Verification ID: $verificationId');
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('[AuthService] SMS code auto-retrieval timed out for: $verificationId');
        },
      );
    } catch (e) {
      onError('Failed to send verification SMS: $e');
    }
  }

  /// Verifies user input [smsCode] against [verificationId] and signs in.
  Future<UserCredential?> verifyOtpAndSignIn({
    required String verificationId,
    required String smsCode,
  }) async {
    final auth = _auth;
    if (auth == null) {
      debugPrint('[AuthService] Firebase uninitialized: Mocking successful sign-in');
      return null;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      return await auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] OTP verification failed: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Signs in or registers user profile in Firestore after successful phone verification.
  Future<AppUser> syncUserProfile({
    required String uid,
    required String phone,
    String? fullName,
    String? email,
    UserRole defaultRole = UserRole.rider,
  }) async {
    // 1. Check if user already exists in Firestore
    final existingUser = await _userService.getUser(uid);
    if (existingUser != null) {
      return existingUser;
    }

    // 2. Create new user profile document
    final newUser = AppUser(
      id: uid,
      phone: phone,
      email: email,
      fullName: (fullName != null && fullName.trim().isNotEmpty) ? fullName.trim() : 'SwiftRide User',
      role: defaultRole,
      rating: 5.0,
      totalRides: 0,
      createdAt: DateTime.now(),
    );

    await _userService.saveUser(newUser);
    return newUser;
  }

  /// Reads custom claims (e.g. role, admin) from the Firebase ID token.
  Future<Map<String, dynamic>> fetchCustomClaims() async {
    final user = currentFirebaseUser;
    if (user == null) return {};

    try {
      final tokenResult = await user.getIdTokenResult(true);
      return tokenResult.claims ?? {};
    } catch (e) {
      debugPrint('[AuthService] Error fetching custom claims: $e');
      return {};
    }
  }

  /// Signs out the active user session.
  Future<void> signOut() async {
    try {
      await _auth?.signOut();
    } catch (e) {
      debugPrint('[AuthService] Error signing out: $e');
    }
  }
}
