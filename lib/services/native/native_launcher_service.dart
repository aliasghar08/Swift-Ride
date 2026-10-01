import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Zero-dependency launcher service interfacing with native Android Intents
/// and iOS UIApplication openURL via MethodChannel.
/// Replaces external dependencies like url_launcher.
class NativeLauncherService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.launcherChannel);

  /// Launches the native phone dialer with prefilled [phoneNumber].
  Future<bool> launchDialer(String phoneNumber) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodLaunchDialer,
        {'phone': phoneNumber},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Launches the native SMS messaging app with prefilled [recipient] and optional [message].
  Future<bool> launchSms(String recipient, {String? message}) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodLaunchSms,
        {
          'phone': recipient,
          'message': message ?? '',
        },
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens an external URL in the default web browser.
  Future<bool> launchUrl(String url) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodLaunchUrl,
        {'url': url},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Launches external native turn-by-turn navigation (Google Maps / Apple Maps).
  Future<bool> launchMapsDirections({
    required double destinationLat,
    required double destinationLng,
    String? destinationLabel,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodLaunchMapsDirections,
        {
          'latitude': destinationLat,
          'longitude': destinationLng,
          'label': destinationLabel ?? 'Destination',
        },
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }
}
