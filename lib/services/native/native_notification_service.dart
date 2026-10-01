import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Zero-dependency notification service interfacing with native Android
/// NotificationManager and iOS UNUserNotificationCenter via MethodChannel.
/// Replaces external dependencies like flutter_local_notifications.
class NativeNotificationService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.notificationChannel);

  /// Requests notification permission from user (Android 13+ POST_NOTIFICATIONS & iOS alerts).
  Future<bool> requestPermissions() async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodRequestNotificationPermissions,
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Displays an immediate native system notification.
  Future<bool> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'swiftride_alerts',
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodShowNotification,
        {
          'id': id,
          'title': title,
          'body': body,
          'payload': payload,
          'channelId': channelId,
        },
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Cancels a specific notification by [id].
  Future<bool> cancelNotification(int id) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodCancelNotification,
        {'id': id},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Cancels all active app notifications.
  Future<bool> cancelAllNotifications() async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodCancelAllNotifications,
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }
}
