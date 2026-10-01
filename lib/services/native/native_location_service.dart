import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import 'native_channel_constants.dart';

class NativeLocationData {
  final double latitude;
  final double longitude;
  final double heading;
  final double speed;
  final bool isMock;

  const NativeLocationData({
    required this.latitude,
    required this.longitude,
    required this.heading,
    this.speed = 0.0,
    this.isMock = false,
  });
}

/// Service interfacing with native iOS CoreLocation and Android FusedLocationProviderClient via MethodChannel.
class NativeLocationService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.locationChannel);

  /// Checks if location permission has been granted on the host OS.
  Future<bool> checkPermissions() async {
    try {
      final res = await _channel.invokeMethod<bool>(NativeChannelConstants.methodCheckLocationPermissions);
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Requests foreground / background GPS permission from the host OS.
  Future<bool> requestPermissions() async {
    try {
      final res = await _channel.invokeMethod<bool>(NativeChannelConstants.methodRequestLocationPermissions);
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Fetches instantaneous GPS fix from the host operating system.
  Future<NativeLocationData> getCurrentCoordinates() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(NativeChannelConstants.methodGetCurrentLocation);
      if (map != null) {
        return NativeLocationData(
          latitude: (map['latitude'] as num?)?.toDouble() ?? AppConstants.defaultLat,
          longitude: (map['longitude'] as num?)?.toDouble() ?? AppConstants.defaultLng,
          heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
          speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
          isMock: map['isMock'] as bool? ?? false,
        );
      }
    } catch (_) {
      // Fallback
    }

    return const NativeLocationData(
      latitude: AppConstants.defaultLat,
      longitude: AppConstants.defaultLng,
      heading: 0.0,
      speed: 0.0,
      isMock: false,
    );
  }
}
