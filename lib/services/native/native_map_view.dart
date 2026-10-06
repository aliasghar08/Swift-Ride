import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';
import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Controller for interacting directly with the native map platform view or method channel.
class NativeMapController {
  final MethodChannel _channel;

  NativeMapController({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(NativeChannelConstants.mapChannel);

  /// Animates native camera to target coordinates.
  Future<bool> animateCamera({
    required double latitude,
    required double longitude,
    double zoom = 15.0,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodMapAnimateCamera,
        {
          'latitude': latitude,
          'longitude': longitude,
          'zoom': zoom,
        },
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Adds a marker to the native map view.
  Future<bool> addMarker({
    required String markerId,
    required double latitude,
    required double longitude,
    required String title,
    String? snippet,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodMapAddMarker,
        {
          'id': markerId,
          'latitude': latitude,
          'longitude': longitude,
          'title': title,
          'snippet': snippet ?? '',
        },
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Clears all markers from native map.
  Future<bool> clearMarkers() async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodMapClearMarkers,
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Sets route polyline points on native map.
  Future<bool> setPolyline(List<Map<String, double>> points) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodMapSetPolyline,
        {'points': points},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Calculates geodesic distance between two points in km using native OS location math.
  Future<double> calculateDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) async {
    try {
      final res = await _channel.invokeMethod<double>(
        NativeChannelConstants.methodMapCalculateDistance,
        {
          'lat1': lat1,
          'lon1': lon1,
          'lat2': lat2,
          'lon2': lon2,
        },
      );
      if (res != null) return res;
    } catch (_) {}
    return 0.0;
  }
}

/// Zero-dependency Native Map Platform View embedding Android / iOS native map
/// views via MethodChannel & Platform Views without requiring third party flutter plugins.
class NativePlatformMapView extends StatelessWidget {
  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final void Function(NativeMapController controller)? onMapCreated;

  const NativePlatformMapView({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialZoom = 15.0,
    this.onMapCreated,
  });

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, dynamic>{
      'latitude': initialLat,
      'longitude': initialLng,
      'zoom': initialZoom,
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'com.swiftride.app/native_map_view',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          onMapCreated?.call(NativeMapController());
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'com.swiftride.app/native_map_view',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          onMapCreated?.call(NativeMapController());
        },
      );
    }

    // Fallback placeholder container for testing/web
    return Container(
      color: AppColors.of(context).canvas,
      child: const Center(
        child: Icon(Icons.map_outlined, color: Colors.cyanAccent, size: 48),
      ),
    );
  }
}
