import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Outcome of a native payment attempt.
///
/// Deliberately has no optimistic default: a charge that did not verifiably
/// succeed is always [isSuccess] == false with a null [transactionId].
/// Never synthesise a transaction id — a fabricated id tells a rider or driver
/// that money moved when it did not.
class NativePaymentResult {
  final bool isSuccess;
  final String? transactionId;
  final String? errorMessage;

  const NativePaymentResult({
    required this.isSuccess,
    this.transactionId,
    this.errorMessage,
  });

  const NativePaymentResult.failure(String message)
      : isSuccess = false,
        transactionId = null,
        errorMessage = message;
}

/// Service interfacing with native Apple Pay (PassKit) / Google Pay and the
/// Stripe payment sheet via MethodChannel.
class NativePaymentService {
  static const MethodChannel _channel =
      MethodChannel(NativeChannelConstants.paymentChannel);

  /// Whether a native wallet is actually available and enrolled on this device.
  ///
  /// Fails closed: if the platform channel is missing or throws, we report
  /// "not supported" rather than assuming a wallet exists.
  Future<Map<String, bool>> checkNativePaySupport() async {
    try {
      final res = await _channel.invokeMapMethod<String, bool>(
        NativeChannelConstants.methodCheckNativePaySupport,
      );
      return {
        'applePay': res?['applePay'] ?? false,
        'googlePay': res?['googlePay'] ?? false,
      };
    } on PlatformException catch (e) {
      debugPrint('[NativePaymentService] checkNativePaySupport failed: ${e.code}');
      return {'applePay': false, 'googlePay': false};
    } on MissingPluginException {
      debugPrint('[NativePaymentService] payment channel unavailable');
      return {'applePay': false, 'googlePay': false};
    }
  }

  /// Presents the native payment sheet and confirms the charge.
  ///
  /// Returns a failure result — never a synthetic success — when the sheet is
  /// dismissed, the charge fails, or the platform channel is unavailable.
  Future<NativePaymentResult> processPayment({
    required String rideId,
    required double amount,
    String currency = 'PKR',
    String method = 'CARD',
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        NativeChannelConstants.methodProcessPayment,
        {
          'rideId': rideId,
          'amount': amount,
          'currency': currency,
          'method': method,
        },
      );

      if (res == null) {
        return const NativePaymentResult.failure(
          'The payment sheet did not return a result. Nothing has been charged.',
        );
      }

      final success = res['success'] as bool? ?? false;
      final txnId = res['transactionId'] as String?;

      // A success without a real transaction id is not a success.
      if (!success || txnId == null || txnId.isEmpty) {
        return NativePaymentResult.failure(
          (res['error'] as String?) ??
              'The payment was not completed. Nothing has been charged.',
        );
      }

      return NativePaymentResult(isSuccess: true, transactionId: txnId);
    } on PlatformException catch (e) {
      return NativePaymentResult.failure(
        e.message ?? 'The payment could not be processed (${e.code}).',
      );
    } on MissingPluginException {
      return const NativePaymentResult.failure(
        'Payments are not available in this build. Nothing has been charged.',
      );
    }
  }
}
