import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
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
  User? get currentUser => currentFirebaseUser;

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
    void Function(String verificationId)? onAutoRetrievalTimeout,
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final auth = _auth;
    if (auth == null) {
      debugPrint('[AuthService] Firebase unavailable: simulating OTP');
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
          debugPrint('[AuthService] Auto-verification completed via Google Play Services.');
          if (onAutoVerified != null) {
            onAutoVerified(credential);
          } else {
            try {
              await auth.signInWithCredential(credential);
            } catch (e) {
              onError(e.toString());
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('[AuthService] Phone verification failed: [${e.code}] ${e.message}');
          String message = '[${e.code}] ${e.message ?? 'Phone verification failed.'}';
          if (e.code == 'invalid-phone-number') {
            message = '[${e.code}] The phone number format is invalid. Please use international format (e.g. +923001234567).';
          } else if (e.code == 'too-many-requests') {
            message = '[${e.code}] Too many requests sent. Please wait a few moments before trying again.';
          } else if (e.code == 'quota-exceeded') {
            message = '[${e.code}] SMS quota exceeded for today.';
          } else if (e.code == 'app-not-authorized') {
            message = '[${e.code}] App not authorized. Ensure SHA-1/SHA-256 fingerprints are registered in Firebase Console.';
          } else if (e.code == 'captcha-check-failed') {
            message = '[${e.code}] reCAPTCHA verification failed. Please check network/Play Services and retry.';
          } else if (e.code == 'invalid-app-credential') {
            message = '[${e.code}] Invalid app credential. Please register SHA-1 and SHA-256 fingerprints in Firebase Console.';
          }
          onError(message);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('[AuthService] OTP code sent successfully. Verification ID: $verificationId');
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('[AuthService] SMS code auto-retrieval timed out for: $verificationId');
          onAutoRetrievalTimeout?.call(verificationId);
        },
      );
    } catch (e) {
      debugPrint('[AuthService] Caught verifyPhoneNumber exception: $e');
      if (!kReleaseMode) {
        debugPrint('[AuthService] Non-release fallback activated: providing test verification ID for local testing');
        onCodeSent('sim_fallback_${DateTime.now().millisecondsSinceEpoch}', 123456);
        return;
      }
      onError('Verification error: $e');
    }
  }

  /// Verifies user input [smsCode] against [verificationId] and signs in.
  /// If an anonymous session exists, seamlessly links it with the verified phone credentials.
  Future<UserCredential?> verifyOtpAndSignIn({
    required String verificationId,
    required String smsCode,
  }) async {
    final auth = _auth;
    if (auth == null) {
      debugPrint('[AuthService] Firebase uninitialized: Mocking successful sign-in');
      return null;
    }

    // Handle simulator/mock test verification IDs (strictly disallowed in release builds)
    if (!kReleaseMode &&
        (verificationId == 'SIMULATOR_TEST_VERIFICATION_ID' ||
            verificationId.startsWith('sim_') ||
            verificationId.startsWith('mock_'))) {
      debugPrint('[AuthService] Verifying test OTP in simulator mode: $smsCode');
      if (smsCode.trim() != '123456') {
        throw FirebaseAuthException(
          code: 'invalid-verification-code',
          message: 'Invalid test OTP code. For test numbers, enter 123456.',
        );
      }

      // Ensure an active Firebase user exists to satisfy Firestore security rules
      if (auth.currentUser == null) {
        try {
          return await auth.signInAnonymously();
        } catch (e) {
          debugPrint('[AuthService] Anonymous sign-in notice: $e');
        }
      }
      return null;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );

      // If user was previously an anonymous guest, upgrade/link the account
      final current = auth.currentUser;
      if (current != null && current.isAnonymous) {
        try {
          debugPrint('[AuthService] Linking anonymous session with phone credential...');
          return await current.linkWithCredential(credential);
        } catch (linkError) {
          debugPrint(
            '[AuthService] linkWithCredential error, falling back to signInWithCredential: $linkError',
          );
        }
      }

      return await auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] OTP verification failed: [${e.code}] ${e.message}');
      rethrow;
    }
  }

  /// Signs in directly with a [PhoneAuthCredential] (e.g. from auto-retrieval).
  Future<UserCredential?> signInWithCredential(PhoneAuthCredential credential) async {
    final auth = _auth;
    if (auth == null) return null;
    return await auth.signInWithCredential(credential);
  }

  /// Signs in or registers user profile in Firestore after successful phone verification.
  /// Calls Cloud Functions to mint cryptographic custom claims on the user's ID token.

  /// Direct wrapper for verifyPhoneNumber matching standard Firebase Phone Auth signatures
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException e) onError,
    void Function(PhoneAuthCredential credential)? verificationCompleted,
  }) async {
    await sendOtp(
      phoneNumber: phoneNumber,
      onCodeSent: (vId, _) => onCodeSent(vId),
      onError: (errMsg) => onError(FirebaseAuthException(code: 'verification-failed', message: errMsg)),
      onAutoVerified: verificationCompleted,
    );
  }

  /// Direct wrapper for signInWithOtp matching standard OTP confirmation signatures
  Future<UserCredential?> signInWithOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    return await verifyOtpAndSignIn(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

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
      // Ensure custom claims are up to date
      try {
        await _auth?.currentUser?.getIdToken(true);
      } catch (_) {}
      return existingUser;
    }

    // 2. Create new user profile document
    final newUser = AppUser(
      id: uid,
      phone: phone,
      email: email,
      fullName: (fullName != null && fullName.trim().isNotEmpty)
          ? fullName.trim()
          : 'SwiftRide User',
      role: defaultRole,
      rating: 5.0,
      totalRides: 0,
      createdAt: DateTime.now(),
    );

    await _userService.saveUser(newUser);

    // 3. Mint custom claims via Cloud Functions & refresh ID token
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseFunctions.instance
            .httpsCallable('registerUser')
            .call(<String, dynamic>{
              'fullName': newUser.fullName,
              'phone': newUser.phone,
              if (email != null && email.isNotEmpty) 'email': email,
              'role': defaultRole.name,
            });
        await _auth?.currentUser?.getIdToken(true);
        debugPrint('[AuthService] User profile and signed claims synchronized');
      }
    } catch (e) {
      debugPrint('[AuthService] registerUser cloud function sync notice: $e');
    }

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

  /// Permanently deletes the active user's Firestore profile, cleans up tokens,
  /// and deletes the Firebase Auth user record.
  /// Complies with Apple App Store Review Guideline 5.1.1(v) for in-app account deletion.
  Future<void> deleteAccount() async {
    final user = currentFirebaseUser;
    final uid = user?.uid;

    if (uid != null && uid.isNotEmpty) {
      // 1. Remove Firestore user document
      try {
        await _userService.deleteUser(uid);
      } catch (e) {
        debugPrint('[AuthService] Error deleting Firestore document for $uid: $e');
      }

      // 2. Invoke server-side deletion Cloud Function if registered
      try {
        if (Firebase.apps.isNotEmpty) {
          await FirebaseFunctions.instance
              .httpsCallable('deleteUserAccount')
              .call(<String, dynamic>{'userId': uid});
        }
      } catch (e) {
        debugPrint('[AuthService] deleteUserAccount function notice: $e');
      }

      // 3. Delete Firebase Auth user
      if (user != null) {
        try {
          await user.delete();
          debugPrint('[AuthService] Firebase Auth user $uid successfully deleted');
        } on FirebaseAuthException catch (e) {
          debugPrint('[AuthService] FirebaseAuthException on user.delete(): [${e.code}] ${e.message}');
          if (e.code == 'requires-recent-login') {
            await signOut();
            rethrow;
          }
        } catch (e) {
          debugPrint('[AuthService] Unexpected error deleting Auth user: $e');
        }
      }
    }

    // Always ensure session is signed out
    await signOut();
  }
}
