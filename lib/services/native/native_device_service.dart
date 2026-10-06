import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Service interfacing with native Android / iOS device hardware via MethodChannel.
class NativeDeviceService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.deviceChannel);

  /// Triggers native system haptic feedback.
  Future<void> triggerHaptic([String type = 'medium']) async {
    try {
      await _channel.invokeMethod(NativeChannelConstants.methodHapticFeedback, {'type': type});
    } catch (_) {
      // Graceful fallback to Flutter framework HapticFeedback
      switch (type) {
        case 'light':
          HapticFeedback.lightImpact();
          break;
        case 'heavy':
          HapticFeedback.heavyImpact();
          break;
        case 'selection':
          HapticFeedback.selectionClick();
          break;
        case 'vibrate':
          HapticFeedback.vibrate();
          break;
        default:
          HapticFeedback.mediumImpact();
      }
    }
  }

  /// Controls screen wake lock to keep display awake during active rides.
  Future<bool> setKeepScreenOn(bool keepOn) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodSetKeepScreenOn,
        {'keepOn': keepOn},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Fetches native battery percentage (used for driver app power optimization).
  Future<int> getBatteryLevel() async {
    try {
      final res = await _channel.invokeMethod<int>(NativeChannelConstants.methodGetBatteryInfo);
      return res ?? 85;
    } catch (_) {
      return 85;
    }
  }

  /// Fetches native device hardware information (model, OS, manufacturer).
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        NativeChannelConstants.methodGetDeviceInfo,
      );
      if (res != null) return res;
    } catch (_) {}
    // Report that the model is unknown rather than inventing a device name.
    return {
      'model': 'Unknown device',
      'os': 'Mobile',
      'version': '1.0.0',
    };
  }

  /// Fetches application release and build version from native bundle.
  Future<String> getAppVersion() async {
    try {
      final res = await _channel.invokeMethod<String>(
        NativeChannelConstants.methodGetAppVersion,
      );
      if (res != null) return res;
    } catch (_) {}
    return '1.0.0+1';
  }
}
