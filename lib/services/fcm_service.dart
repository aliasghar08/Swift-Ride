import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firestore/firestore_user_service.dart';
import 'native/native_notification_service.dart';

/// Background message handler.
///
/// Must be a top-level function so it survives in a separate isolate when the
/// app is terminated. It deliberately does no app work: Android and iOS display
/// the `notification` payload themselves, and touching Firebase here would need
/// its own initialisation.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    '[FCM] background message ${message.messageId} type=${message.data['type']}',
  );
}

/// Registers this device for push and routes incoming messages.
///
/// The backend has always sent FCM — `triggerSos` fans out to the `fcmTokens` on
/// each user document — but nothing on the client ever registered a token or
/// listened for a message. `fcmTokens` was therefore permanently empty, so every
/// push in the app was a no-op: SOS alerts, ride dispatch and driver approvals
/// all silently reached nobody.
class FcmService {
  FcmService({
    FirestoreUserService? userService,
    NativeNotificationService? notificationService,
  })  : _users = userService ?? FirestoreUserService(),
        _notifications = notificationService ?? NativeNotificationService();

  final FirestoreUserService _users;
  final NativeNotificationService _notifications;

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;

  String? _userId;
  String? _token;

  /// Invoked when a message is tapped (app backgrounded or launched from it).
  void Function(RemoteMessage message)? onMessageOpened;

  /// True once a device token has been obtained and persisted.
  bool get isRegistered => _token != null;

  String? get token => _token;

  /// Requests permission, registers this device, and starts listening.
  ///
  /// Returns false when push cannot be set up on this platform, so callers can
  /// report the real situation rather than assuming alerts will arrive.
  Future<bool> initialize({required String userId}) async {
    if (kIsWeb || userId.isEmpty || Firebase.apps.isEmpty) return false;

    _userId = userId;

    try {
      final messaging = FirebaseMessaging.instance;

      // iOS prompts here; Android 13+ needs POST_NOTIFICATIONS, which the native
      // channel requests. A denial is not fatal — the token is still worth
      // registering so notifications work once the user enables them.
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Without this, an iOS app in the foreground shows nothing at all.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _token = await messaging.getToken();
      if (_token != null) {
        await _users.addFcmToken(userId, _token!);
      }

      _tokenRefreshSub = messaging.onTokenRefresh.listen((fresh) {
        _token = fresh;
        final uid = _userId;
        if (uid != null) unawaited(_users.addFcmToken(uid, fresh));
      });

      _foregroundSub = FirebaseMessaging.onMessage.listen(_showForeground);

      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        onMessageOpened?.call(message);
      });

      // App launched from a terminated state by tapping a notification.
      final initial = await messaging.getInitialMessage();
      if (initial != null) onMessageOpened?.call(initial);

      return _token != null;
    } catch (e) {
      debugPrint('[FcmService] initialize failed: $e');
      return false;
    }
  }

  /// Displays a message that arrived while the app was in the foreground.
  ///
  /// Neither platform surfaces notification payloads on its own in this state.
  Future<void> _showForeground(RemoteMessage message) async {
    final isSos = message.data['type'] == 'SOS';

    await _notifications.showNotification(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: message.notification?.title ?? (isSos ? '🚨 EMERGENCY SOS' : 'SwiftRide'),
      body: message.notification?.body ?? '',
      // The SOS channel is high-importance and bypasses Do Not Disturb grouping.
      channelId: isSos ? 'swiftride_emergency' : 'swiftride_alerts',
      payload: jsonEncode(message.data),
    );
  }

  /// Unregisters this device, e.g. on sign-out.
  ///
  /// Without this, a signed-out device keeps receiving another account's SOS
  /// alerts and trip notifications.
  Future<void> unregister() async {
    final uid = _userId;
    final current = _token;

    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _tokenRefreshSub = null;

    try {
      if (uid != null && current != null) {
        await _users.removeFcmToken(uid, current);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[FcmService] unregister failed: $e');
    }

    _userId = null;
    _token = null;
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedSub?.cancel();
    _tokenRefreshSub?.cancel();
  }
}
