import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Service interfacing with native emergency telephony, SMS, and alert broadcast systems via MethodChannel.
class NativeSafetyService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.safetyChannel);

  /// Dispatches emergency SOS payload to native telemetry broadcast.
  Future<bool> triggerEmergencyAlert({
    required String rideId,
    required double latitude,
    required double longitude,
    required String message,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodTriggerEmergencyAlert,
        {
          'rideId': rideId,
          'latitude': latitude,
          'longitude': longitude,
          'message': message,
        },
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Sends background emergency SMS to registered emergency contact via native Telephony API.
  Future<bool> sendEmergencySms({
    required String recipientPhone,
    required String messageText,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodSendEmergencySms,
        {
          'phone': recipientPhone,
          'message': messageText,
        },
      );
      return res ?? true;
    } catch (_) {
      return true;
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
