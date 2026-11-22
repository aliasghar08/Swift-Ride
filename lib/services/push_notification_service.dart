import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Must be a top-level function for background/terminated isolate execution.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  debugPrint('FCM Background Message: ${message.messageId} | ${message.data}');
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const String webVapidKey =
      'BIkT-JAqg_eWAUN0U_CVemQ3GmTWuLrrdO6KRmZ1pPLQrAoFqJErAIu4L6HS97dVR25FStVLuEItda4xUXnzndk';

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;

  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onNotificationTap,
  }) async {
    if (Firebase.apps.isEmpty) {
      debugPrint('[PushNotificationService] Firebase uninitialized; skipping setup.');
      return;
    }
    if (_initialized) return;
    _initialized = true;

    try {
      // 1. Register background handler (non-web)
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }

      // 2. Request OS permission (iOS & Android 13+)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push notifications denied by user.');
        return;
      }

      // 3. Ensure foreground alerts show on iOS
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Fetch & sync current token
      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? webVapidKey : null,
      );
      if (token != null) {
        await syncTokenToFirestore(token);
      }

      // 5. Listen for token rotations
      _tokenRefreshSub = _messaging.onTokenRefresh.listen(syncTokenToFirestore);

      // 6. Foreground message stream
      _foregroundSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground FCM: ${message.notification?.title} | type=${message.data['type']}');
      });

      // 7. Handle tap when app is in background
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        onNotificationTap(message.data);
      });

      // 8. Handle tap when app was terminated
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        onNotificationTap(initialMessage.data);
      }
    } catch (e) {
      debugPrint('[PushNotificationService] initialize notice: $e');
    }
  }

  Future<void> syncTokenToFirestore(String token) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;

      final payload = {
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      };

      // Update both user profile and driver profile (if active driver)
      await _db.collection('users').doc(uid).set(payload, SetOptions(merge: true));
      final driverRef = _db.collection('drivers').doc(uid);
      DocumentSnapshot<Map<String, dynamic>>? driverSnap;
      try {
        driverSnap = await driverRef.get();
      } catch (_) {}
      if (driverSnap != null && driverSnap.exists) {
        await driverRef.update(payload).catchError((_) {});
      }
    } catch (e) {
      debugPrint('[PushNotificationService] syncTokenToFirestore notice: $e');
    }
  }

  Future<void> removeCurrentTokenOnLogout() async {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? webVapidKey : null,
      ).catchError((_) => null);

      if (uid != null && uid.isNotEmpty && token != null) {
        await _db.collection('users').doc(uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }).catchError((_) {});

        final driverRef = _db.collection('drivers').doc(uid);
        DocumentSnapshot<Map<String, dynamic>>? driverSnap;
        try {
          driverSnap = await driverRef.get();
        } catch (_) {}
        if (driverSnap != null && driverSnap.exists) {
          await driverRef.update({
            'fcmTokens': FieldValue.arrayRemove([token]),
          }).catchError((_) {});
        }
      }
      await _messaging.deleteToken().catchError((_) {});
    } catch (e) {
      debugPrint('[PushNotificationService] removeCurrentTokenOnLogout notice: $e');
    }
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
    _tokenRefreshSub?.cancel();
    _initialized = false;
  }
}
