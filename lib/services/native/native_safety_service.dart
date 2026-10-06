import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Service interfacing with native emergency telephony, SMS, and alert broadcast systems via MethodChannel.
class NativeSafetyService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.safetyChannel);

  /// Opens the device's SMS composer, prefilled and addressed.
  ///
  /// Returns true only when the composer was actually presented. The user still
  /// has to press send, so a true result does not mean a message was delivered —
  /// callers must not describe it that way.
  ///
  /// This used to return `true` unconditionally: the native handlers were stubs
  /// that did nothing, so the app reported an emergency SMS that was never even
  /// composed.
  Future<bool> sendEmergencySms({
    required String recipientPhone,
    required String messageText,
  }) async {
    if (recipientPhone.trim().isEmpty) return false;

    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodSendEmergencySms,
        {
          'phone': recipientPhone,
          'message': messageText,
        },
      );
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeSafetyService] sendEmergencySms failed: $e');
      return false;
    }
  }

  /// Pulses hardware vibration motor in SOS pattern (... --- ...).
  Future<void> triggerEmergencyHaptics() async {
    try {
      await _channel.invokeMethod(NativeChannelConstants.methodTriggerEmergencyHaptics);
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }
}
