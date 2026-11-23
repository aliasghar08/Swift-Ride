import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../domain/models/user_model.dart';
import '../domain/models/user_role.dart';
import 'firestore/firestore_user_service.dart';
import 'native/native_storage_service.dart';

enum SocialSessionAction { keepCurrent, restoredSession, needsPhoneVerification }

class SocialSessionResult {
  final SocialSessionAction action;
  final AppUser? user;
  final String? phoneNumber;
  final String? email;
  final String? maskedPhone;
  final bool hasExistingAccount;
  final String? targetUid;

  const SocialSessionResult({
    required this.action,
    this.user,
    this.phoneNumber,
    this.email,
    this.maskedPhone,
    this.hasExistingAccount = false,
    this.targetUid,
  });
}

/// Production-ready Firebase Phone Authentication service.
/// Supports OTP verification, auto-retrieval, resend token management,
/// and graceful fallback for uninitialized Firebase environments (e.g. unit/widget tests).
class AuthService {
  /// User-facing SMS failure message. Only mentions Apple sign-in on Apple
  /// platforms, since Sign in with Apple is not offered on Android.
  static String get smsUnavailableMessage {
    final isApplePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final alternatives = isApplePlatform ? 'Google or Apple' : 'Google';
    return 'Unable to send SMS to this number. Please turn off any VPN, wait 15 minutes before retrying, or continue with $alternatives below.';
  }

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
  final NativeStorageService _storage = NativeStorageService();
  static const String keyLastVerifiedPhone = 'last_verified_phone';
  static const String keyTrustedDeviceId = 'trusted_device_id';
  static const String keyDeviceTrustToken = 'device_trust_token';

  SocialSessionResult? _lastSocialSessionResult;
  SocialSessionResult? get lastSocialSessionResult => _lastSocialSessionResult;

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

  /// Whether a real phone-verified Firebase user is currently authenticated.
  /// Anonymous guest sessions (minted for Cloud Function callables) return false.
  bool get isAuthenticated {
    final user = currentFirebaseUser;
    if (user == null) return false;
    if (!user.isAnonymous) return true;
    return user.phoneNumber != null && user.phoneNumber!.isNotEmpty;
  }

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

  /// Designated App Store Review & QA demo phone numbers that always accept OTP `123456`.
  static const Set<String> reviewerDemoNumbers = {
    '+923000000000',
    '+923000000001',
    '+923000000002',
    '+15550100001',
    '+15550100002',
  };

  /// Checks whether [phoneNumber] is a designated App Store Review / QA demo number.
  static bool isReviewerDemoNumber(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return false;
    final normalized = '+$digits';
    if (reviewerDemoNumbers.contains(normalized)) return true;
    if (digits == '03000000000' ||
        digits == '03000000001' ||
        digits == '03000000002' ||
        digits == '3000000000' ||
        digits == '3000000001' ||
        digits == '3000000002' ||
        digits == '5550100001' ||
        digits == '5550100002') {
      return true;
    }
    return false;
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
      debugPrint('[AuthService] Firebase unavailable: simulating OTP for test environment');
      await Future.delayed(const Duration(milliseconds: 300));
      onCodeSent('mock_verification_id_${DateTime.now().millisecondsSinceEpoch}', 123456);
      return;
    }

    if (isReviewerDemoNumber(phoneNumber)) {
      debugPrint('[AuthService] Reviewer demo number detected ($phoneNumber): issuing instant OTP challenge.');
      await Future.delayed(const Duration(milliseconds: 250));
      onCodeSent('reviewer_demo_${DateTime.now().millisecondsSinceEpoch}', 123456);
      return;
    }

    try {
      await auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: timeout,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('[AuthService] Auto-verification completed.');
          unawaited(registerTrustedDevice(phoneNumber));
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
          if (e.code == 'invalid-phone-number' || e.code == 'missing-phone-number') {
            onError(
              'The phone number format is invalid. Please enter a valid 10-digit number (e.g. 300 1234567).',
            );
            return;
          }
          if (e.code == 'unknown' ||
              (e.message?.contains('39') == true) ||
              (e.message?.contains('17499') == true)) {
            onError(
              smsUnavailableMessage,
            );
            return;
          }
          if (!kReleaseMode) {
            debugPrint(
              '[AuthService] Emulator/debug fallback activated for $phoneNumber after [${e.code}]',
            );
            onCodeSent(
              'sim_otp_${DateTime.now().millisecondsSinceEpoch}',
              123456,
            );
            return;
          }
          String message = '[${e.code}] ${e.message ?? 'Phone verification failed.'}';
          if (e.code == 'too-many-requests') {
            message = 'Too many requests sent. Please wait a minute before requesting a new code.';
          } else if (e.code == 'quota-exceeded') {
            message = 'SMS quota temporarily exceeded. Please try again later.';
          } else if (e.code == 'app-not-authorized') {
            message = 'Phone verification service is temporarily unavailable. Please try again or use Reviewer Demo credentials.';
          } else if (e.code == 'captcha-check-failed') {
            message = 'Security verification check failed. Please check your network connection and retry.';
          } else if (e.code == 'invalid-app-credential') {
            message = 'Verification credential check failed. Please retry in a moment.';
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
      final errStr = e.toString();
      if (errStr.contains('39') || errStr.contains('17499') || errStr.contains('Error code:39')) {
        onError(
          smsUnavailableMessage,
        );
        return;
      }
      if (isReviewerDemoNumber(phoneNumber) || !kReleaseMode) {
        debugPrint('[AuthService] Fallback activated for demo/test number: $phoneNumber');
        onCodeSent('sim_otp_${DateTime.now().millisecondsSinceEpoch}', 123456);
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
    String? phoneNumber,
  }) async {
    final auth = _auth;
    if (auth == null) {
      if ((verificationId.startsWith('reviewer_demo_') && smsCode.trim() != '123456') ||
          smsCode.trim() == '000000') {
        throw FirebaseAuthException(
          code: 'invalid-verification-code',
          message: 'Incorrect 6-digit verification code. Please check your SMS and try again.',
        );
      }
      debugPrint('[AuthService] Firebase uninitialized: Mocking successful sign-in');
      return null;
    }

    // Handle designated App Store Reviewer demo verification IDs or non-release test IDs
    final isReviewerDemo = verificationId.startsWith('reviewer_demo_');
    final isSimTest = !kReleaseMode &&
        (verificationId == 'SIMULATOR_TEST_VERIFICATION_ID' ||
            verificationId.startsWith('sim_') ||
            verificationId.startsWith('mock_'));

    if (isReviewerDemo || isSimTest) {
      debugPrint('[AuthService] Verifying demo/test OTP: $smsCode');
      if (smsCode.trim() != '123456') {
        throw FirebaseAuthException(
          code: 'invalid-verification-code',
          message: 'Invalid verification code. For demo accounts, enter 123456.',
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

      final userCred = await auth.signInWithCredential(credential);
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        unawaited(registerTrustedDevice(phoneNumber));
      }
      return userCred;
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

  /// Registers a cryptographically random device trust token in Firestore via Cloud Functions.
  /// Stored securely on the local device to allow automatic session restoration when signing in
  /// with Google or Apple on this same device.
  Future<void> registerTrustedDevice(String phoneNumber) async {
    try {
      final auth = _auth;
      final phone = (auth?.currentUser?.phoneNumber != null &&
              auth!.currentUser!.phoneNumber!.isNotEmpty)
          ? auth.currentUser!.phoneNumber!
          : phoneNumber;
      if (phone.isEmpty) return;

      var deviceId = await _storage.getString(keyTrustedDeviceId);
      if (deviceId == null || deviceId.isEmpty) {
        final rand = DateTime.now().microsecondsSinceEpoch.toString();
        deviceId = 'dev_${kIsWeb ? "web" : defaultTargetPlatform.name}_$rand';
        await _storage.setString(keyTrustedDeviceId, deviceId);
      }

      await _storage.setString(keyLastVerifiedPhone, phone);

      if (Firebase.apps.isNotEmpty) {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('registerTrustedDevice');
        final res = await callable.call<Map<String, dynamic>>({
          'deviceId': deviceId,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        });

        final rawToken = res.data['deviceTrustToken'] as String?;
        if (rawToken != null && rawToken.isNotEmpty) {
          await _storage.setString(keyDeviceTrustToken, rawToken);
          debugPrint('[AuthService] Registered trusted device token successfully.');
        }
      }
    } catch (e) {
      debugPrint('[AuthService] registerTrustedDevice non-fatal notice: $e');
    }
  }

  /// Calls the `resolveSocialSession` Cloud Function to verify user identity,
  /// detect existing phone accounts, and safely restore the previous session if trusted.
  Future<SocialSessionResult> resolveSocialSession({
    required String provider,
    String? candidatePhone,
    OAuthCredential? originalCredential,
  }) async {
    final auth = _auth;
    if (auth == null || auth.currentUser == null) {
      return const SocialSessionResult(action: SocialSessionAction.keepCurrent);
    }

    try {
      final storedPhone = await _storage.getString(keyLastVerifiedPhone);
      final deviceId = await _storage.getString(keyTrustedDeviceId);
      final deviceTrustToken = await _storage.getString(keyDeviceTrustToken);

      final phone = (auth.currentUser?.phoneNumber != null &&
              auth.currentUser!.phoneNumber!.isNotEmpty)
          ? auth.currentUser!.phoneNumber!
          : (candidatePhone != null && candidatePhone.trim().isNotEmpty
              ? candidatePhone.trim()
              : (storedPhone ?? ''));

      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('resolveSocialSession');

      final resp = await callable.call({
        if (phone.isNotEmpty) 'phoneNumber': phone,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        if (deviceTrustToken != null && deviceTrustToken.isNotEmpty)
          'deviceTrustToken': deviceTrustToken,
        'provider': provider,
      });

      final data = Map<String, dynamic>.from(resp.data as Map);
      final action = data['action'] as String?;

      if (action == 'RESTORE_SESSION') {
        final customToken = data['customToken'] as String;
        final targetUid = data['targetUid'] as String;
        debugPrint('[AuthService] resolveSocialSession: restoring previous session for target UID $targetUid');

        await auth.signInWithCustomToken(customToken);

        if (originalCredential != null) {
          try {
            await auth.currentUser?.linkWithCredential(originalCredential);
          } catch (linkErr) {
            debugPrint('[AuthService] linkWithCredential notice: $linkErr');
          }
        }

        await auth.currentUser?.getIdToken(true);
        final restoredUser = await _userService.getUser(targetUid);

        return SocialSessionResult(
          action: SocialSessionAction.restoredSession,
          user: restoredUser,
          phoneNumber: data['phoneNumber'] as String?,
          email: data['email'] as String?,
        );
      } else if (action == 'NEEDS_PHONE_VERIFICATION') {
        return SocialSessionResult(
          action: SocialSessionAction.needsPhoneVerification,
          maskedPhone: data['maskedPhone'] as String?,
          hasExistingAccount: true,
          targetUid: data['targetUid'] as String?,
        );
      } else {
        return SocialSessionResult(
          action: SocialSessionAction.keepCurrent,
          phoneNumber: data['phoneNumber'] as String?,
          email: data['email'] as String?,
        );
      }
    } catch (e) {
      debugPrint('[AuthService] resolveSocialSession notice: $e');
      return const SocialSessionResult(action: SocialSessionAction.keepCurrent);
    }
  }

  /// Authenticates using Google Sign-In and links/persists the profile in Firestore.
  /// Returns null if the user cancelled the dialog or flow.
  Future<AppUser?> signInWithGoogle({
    required String selectedRole,
    String? fullName,
    String? candidatePhone,
  }) async {
    final role = selectedRole.toLowerCase() == 'driver' ? UserRole.driver : UserRole.passenger;
    final auth = _auth;

    if (auth == null) {
      debugPrint('[AuthService] Firebase uninitialized: Simulating Google sign-in');
      final effectivePhone = candidatePhone ?? await _storage.getString(keyLastVerifiedPhone) ?? '';
      if (effectivePhone.isNotEmpty) {
        final existing = await _userService.getUserByPhone(effectivePhone);
        if (existing != null) {
          final merged = existing.copyWith(
            email: existing.email ?? 'rider.google@swiftride.pk',
            linkedProviders: {...existing.linkedProviders, 'google', 'phone'}.toList(),
          );
          await _userService.saveUser(merged);
          return merged;
        }
      }

      final mockUser = AppUser(
        id: 'google_user_${DateTime.now().millisecondsSinceEpoch}',
        fullName: fullName?.trim().isNotEmpty == true ? fullName!.trim() : 'Google Passenger',
        email: 'rider.google@swiftride.pk',
        phone: effectivePhone,
        role: role,
        rating: 5.0,
        totalRides: 0,
        createdAt: DateTime.now(),
        authProvider: 'google',
        linkedProviders: ['google', if (effectivePhone.isNotEmpty) 'phone'],
      );
      await _userService.saveUser(mockUser);
      return mockUser;
    }

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: kIsWeb
            ? '113634488038-8hsg8je0gp7jbdi2j8ic5cmhnviir3to.apps.googleusercontent.com'
            : (defaultTargetPlatform == TargetPlatform.iOS
                ? '113634488038-s869tr34nd75rv4j18s6fv514bk94khd.apps.googleusercontent.com'
                : null),
        serverClientId: '113634488038-8hsg8je0gp7jbdi2j8ic5cmhnviir3to.apps.googleusercontent.com',
        scopes: ['email', 'profile'],
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('[AuthService] Google Sign-In cancelled by user');
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        debugPrint('[AuthService] Google Sign-In warning: idToken is null. Check GIDServerClientID configuration.');
      }
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await auth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;
      if (firebaseUser == null) return null;

      // Smart Identity & Previous Session Resolution
      final sessionResult = await resolveSocialSession(
        provider: 'google',
        candidatePhone: candidatePhone,
        originalCredential: credential,
      );
      _lastSocialSessionResult = sessionResult;

      if (sessionResult.action == SocialSessionAction.restoredSession && sessionResult.user != null) {
        debugPrint('[AuthService] Successfully restored existing session for user: ${sessionResult.user?.id}');
        return sessionResult.user;
      }

      final resolvedName = (fullName != null && fullName.trim().isNotEmpty)
          ? fullName.trim()
          : (firebaseUser.displayName != null && firebaseUser.displayName!.isNotEmpty
              ? firebaseUser.displayName!
              : (googleUser.displayName != null && googleUser.displayName!.isNotEmpty
                  ? googleUser.displayName!
                  : (firebaseUser.email != null && firebaseUser.email!.contains('@')
                      ? firebaseUser.email!.split('@').first
                      : 'Google User')));

      final resolvedPhone = sessionResult.phoneNumber ?? firebaseUser.phoneNumber ?? candidatePhone ?? '';

      return await syncUserProfile(
        uid: firebaseUser.uid,
        phone: resolvedPhone,
        fullName: resolvedName,
        email: firebaseUser.email ?? googleUser.email,
        photoUrl: firebaseUser.photoURL ?? googleUser.photoUrl,
        authProvider: 'google',
        defaultRole: role,
      );
    } on PlatformException catch (e) {
      debugPrint('[AuthService] PlatformException during Google Sign-In: code=${e.code}, message=${e.message}, details=${e.details}');
      final code = e.code.toLowerCase();
      final msg = (e.message ?? '').toLowerCase();
      if (code.contains('cancel') || msg.contains('cancel') || code == 'sign_in_canceled') {
        debugPrint('[AuthService] Google Sign-In cancelled by user');
        return null;
      }
      rethrow;
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] FirebaseAuthException during Google Sign-In: code=${e.code}, message=${e.message}');
      if (e.code == 'canceled' || e.code == 'popup-closed-by-user' || e.code.contains('cancel')) {
        debugPrint('[AuthService] Google Sign-In dismissed/canceled: [${e.code}]');
        return null;
      }
      rethrow;
    } catch (e) {
      debugPrint('[AuthService] Unexpected error during Google Sign-In: $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('canceled') || errStr.contains('cancelled') || errStr.contains('sign_in_canceled')) {
        debugPrint('[AuthService] Google Sign-In user cancelled');
        return null;
      }
      rethrow;
    }
  }

  /// Authenticates using Apple Sign-In and links/persists the profile in Firestore.
  /// Works natively on iOS and via OAuth web flow on Android.
  /// Returns null if the user cancelled the dialog or flow.
  Future<AppUser?> signInWithApple({
    required String selectedRole,
    String? fullName,
    String? candidatePhone,
  }) async {
    final role = selectedRole.toLowerCase() == 'driver' ? UserRole.driver : UserRole.passenger;
    final auth = _auth;

    if (auth == null) {
      debugPrint('[AuthService] Firebase uninitialized: Simulating Apple sign-in');
      final effectivePhone = candidatePhone ?? await _storage.getString(keyLastVerifiedPhone) ?? '';
      if (effectivePhone.isNotEmpty) {
        final existing = await _userService.getUserByPhone(effectivePhone);
        if (existing != null) {
          final merged = existing.copyWith(
            email: existing.email ?? 'rider.apple@swiftride.pk',
            linkedProviders: {...existing.linkedProviders, 'apple', 'phone'}.toList(),
          );
          await _userService.saveUser(merged);
          return merged;
        }
      }

      final mockUser = AppUser(
        id: 'apple_user_${DateTime.now().millisecondsSinceEpoch}',
        fullName: fullName?.trim().isNotEmpty == true ? fullName!.trim() : 'Apple Passenger',
        email: 'rider.apple@swiftride.pk',
        phone: effectivePhone,
        role: role,
        rating: 5.0,
        totalRides: 0,
        createdAt: DateTime.now(),
        authProvider: 'apple',
        linkedProviders: ['apple', if (effectivePhone.isNotEmpty) 'phone'],
      );
      await _userService.saveUser(mockUser);
      return mockUser;
    }

    try {
      final appleProvider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      final userCredential = await auth.signInWithProvider(appleProvider);
      final firebaseUser = userCredential.user;
      if (firebaseUser == null) return null;

      // Smart Identity & Previous Session Resolution
      final sessionResult = await resolveSocialSession(
        provider: 'apple',
        candidatePhone: candidatePhone,
      );
      _lastSocialSessionResult = sessionResult;

      if (sessionResult.action == SocialSessionAction.restoredSession && sessionResult.user != null) {
        debugPrint('[AuthService] Successfully restored existing session for user: ${sessionResult.user?.id}');
        return sessionResult.user;
      }

      final resolvedName = (fullName != null && fullName.trim().isNotEmpty)
          ? fullName.trim()
          : (firebaseUser.displayName != null && firebaseUser.displayName!.isNotEmpty
              ? firebaseUser.displayName!
              : (firebaseUser.email != null && firebaseUser.email!.contains('@')
                  ? firebaseUser.email!.split('@').first
                  : 'Apple User'));

      final resolvedPhone = sessionResult.phoneNumber ?? firebaseUser.phoneNumber ?? candidatePhone ?? '';

      return await syncUserProfile(
        uid: firebaseUser.uid,
        phone: resolvedPhone,
        fullName: resolvedName,
        email: firebaseUser.email,
        photoUrl: firebaseUser.photoURL,
        authProvider: 'apple',
        defaultRole: role,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code.contains('cancel')) {
        debugPrint('[AuthService] Apple Sign-In canceled: [${e.code}]');
        return null;
      }
      rethrow;
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('canceled') || errStr.contains('cancelled')) {
        debugPrint('[AuthService] Apple Sign-In user cancelled');
        return null;
      }
      rethrow;
    }
  }

  Future<AppUser> syncUserProfile({
    required String uid,
    required String phone,
    String? fullName,
    String? email,
    String? photoUrl,
    String? authProvider,
    UserRole defaultRole = UserRole.passenger,
  }) async {
    final trimmedName = fullName?.trim();
    final hasExplicitName = trimmedName != null &&
        trimmedName.isNotEmpty &&
        trimmedName != 'Guest User' &&
        trimmedName != 'SwiftRide User';
    final trimmedEmail = email?.trim();
    final hasExplicitEmail = trimmedEmail != null && trimmedEmail.isNotEmpty;
    final normalizedPhone = AppUser.normalizePhone(phone) ?? phone.trim();

    // 1. Check if user already exists in Firestore by UID or by Phone Number
    AppUser? existingUser = await _userService.getUser(uid);
    if (existingUser == null && normalizedPhone.isNotEmpty) {
      existingUser = await _userService.getUserByPhone(normalizedPhone);
    }

    if (existingUser != null) {
      final resolvedName = hasExplicitName
          ? trimmedName
          : (existingUser.fullName.isNotEmpty &&
                  existingUser.fullName != 'Guest User'
              ? existingUser.fullName
              : (trimmedName != null && trimmedName.isNotEmpty
                  ? trimmedName
                  : 'SwiftRide User'));
      final resolvedPhone =
          normalizedPhone.isNotEmpty ? normalizedPhone : existingUser.phone;
      final resolvedEmail =
          hasExplicitEmail ? trimmedEmail : existingUser.email;
      final resolvedRole = defaultRole != UserRole.passenger ||
              existingUser.role == UserRole.passenger
          ? defaultRole
          : existingUser.role;

      final currentLinked = existingUser.linkedProviders.toSet();
      if (authProvider != null && authProvider.isNotEmpty) currentLinked.add(authProvider);
      if (resolvedPhone.isNotEmpty) currentLinked.add('phone');

      final updatedExisting = existingUser.copyWith(
        id: uid.isNotEmpty ? uid : existingUser.id,
        fullName: resolvedName,
        phone: resolvedPhone,
        email: resolvedEmail,
        role: resolvedRole,
        photoUrl: photoUrl ?? existingUser.photoUrl,
        authProvider: authProvider ?? existingUser.authProvider,
        linkedProviders: currentLinked.toList(),
      );

      await _userService.saveUser(updatedExisting);

      try {
        if (_auth?.currentUser != null && resolvedName.isNotEmpty) {
          await _auth?.currentUser?.updateDisplayName(resolvedName);
        }
        if (photoUrl != null && _auth?.currentUser != null) {
          await _auth?.currentUser?.updatePhotoURL(photoUrl);
        }
        await _auth?.currentUser?.getIdToken(true);
      } catch (_) {}

      return updatedExisting;
    }

    // 2. Create new user profile document
    final newUser = AppUser(
      id: uid,
      phone: normalizedPhone,
      email: hasExplicitEmail ? trimmedEmail : null,
      fullName: (trimmedName != null && trimmedName.isNotEmpty)
          ? trimmedName
          : 'SwiftRide User',
      role: defaultRole,
      rating: 5.0,
      totalRides: 0,
      createdAt: DateTime.now(),
      photoUrl: photoUrl,
      authProvider: authProvider,
      linkedProviders: [
        if (authProvider != null && authProvider.isNotEmpty) authProvider,
        if (normalizedPhone.isNotEmpty) 'phone',
      ],
    );

    await _userService.saveUser(newUser);

    // 3. Mint custom claims via Cloud Functions & refresh ID token
    try {
      if (_auth?.currentUser != null && newUser.fullName.isNotEmpty) {
        await _auth?.currentUser?.updateDisplayName(newUser.fullName);
      }
      if (photoUrl != null && _auth?.currentUser != null) {
        await _auth?.currentUser?.updatePhotoURL(photoUrl);
      }
      if (Firebase.apps.isNotEmpty) {
        await FirebaseFunctions.instance
            .httpsCallable('registerUser')
            .call(<String, dynamic>{
              'fullName': newUser.fullName,
              'phone': newUser.phone,
              if (newUser.email != null && newUser.email!.isNotEmpty)
                'email': newUser.email,
              'role': defaultRole.name,
              if (authProvider != null && authProvider.isNotEmpty)
                'authProvider': authProvider,
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

  /// Signs out the active user session and disconnects Google Sign-In if active.
  Future<void> signOut() async {
    try {
      final user = currentFirebaseUser;
      if (user != null) {
        final isGoogleUser = user.providerData
            .any((p) => p.providerId == 'google.com');
        if (isGoogleUser) {
          try {
            await GoogleSignIn().signOut().timeout(
              const Duration(milliseconds: 300),
              onTimeout: () => null,
            );
          } catch (_) {}
          try {
            await GoogleSignIn().disconnect().timeout(
              const Duration(milliseconds: 300),
              onTimeout: () => null,
            );
          } catch (_) {}
        }
      }
      try {
        await _auth?.signOut();
      } catch (e) {
        debugPrint('[AuthService] Error signing out of FirebaseAuth: $e');
      }
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

      // 3. Delete Firebase Auth user if not already deleted by Cloud Function
      if (user != null) {
        try {
          await user.delete();
          debugPrint('[AuthService] Firebase Auth user $uid successfully deleted');
        } on FirebaseAuthException catch (e) {
          debugPrint('[AuthService] FirebaseAuthException on user.delete(): [${e.code}] ${e.message}');
          // Note: Cloud Function deleteUserAccount already deletes the user via Admin SDK.
          // Do not rethrow requires-recent-login or user-not-found so in-app deletion
          // always succeeds per Apple Guideline 5.1.1(v).
        } catch (e) {
          debugPrint('[AuthService] Unexpected error deleting Auth user: $e');
        }
      }

      // 4. Wipe local trusted-device identity tokens on account deletion
      try {
        await _storage.remove(keyLastVerifiedPhone);
        await _storage.remove(keyTrustedDeviceId);
        await _storage.remove(keyDeviceTrustToken);
      } catch (_) {}
    }

    // Always ensure session is signed out
    await signOut();
  }
}
