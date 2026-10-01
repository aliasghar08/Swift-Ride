import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

enum NetworkStatus { wifi, cellular, ethernet, none, unknown }

/// Zero-dependency network connectivity monitoring service using native Android
/// ConnectivityManager and iOS NWPathMonitor via MethodChannel.
/// Replaces external dependencies like connectivity_plus.
class NativeConnectivityService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.connectivityChannel);

  /// Checks the current device network connection status.
  Future<NetworkStatus> getConnectivityStatus() async {
    try {
      final statusStr = await _channel.invokeMethod<String>(
        NativeChannelConstants.methodGetConnectivityStatus,
      );
      switch (statusStr) {
        case 'wifi':
          return NetworkStatus.wifi;
        case 'cellular':
          return NetworkStatus.cellular;
        case 'ethernet':
          return NetworkStatus.ethernet;
        case 'none':
          return NetworkStatus.none;
        default:
          return NetworkStatus.wifi;
      }
    } catch (_) {
      return NetworkStatus.wifi;
    }
  }

  /// Returns true if the device currently has active internet connectivity.
  Future<bool> isConnected() async {
    final status = await getConnectivityStatus();
    return status != NetworkStatus.none;
  }
}
