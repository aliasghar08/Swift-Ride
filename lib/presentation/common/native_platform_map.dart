import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../services/native_map_service.dart';

export '../../services/native_map_service.dart';

/// Native PlatformView embedding our custom Kotlin NativeMapView on Android
/// and Swift NativeMapView on iOS.
class NativePlatformMap extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final bool darkMode;
  final bool showTraffic;
  final String? mapStyle;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final ValueChanged<LatLng>? onMapTap;
  final ValueChanged<LatLng>? onCameraIdle;
  final ValueChanged<LatLng>? onCameraMove;
  final ValueChanged<NativeMapController>? onMapCreated;
  final VoidCallback? onMapReady;

  const NativePlatformMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15.0,
    this.darkMode = false,
    this.showTraffic = false,
    this.mapStyle,
    this.markers = const {},
    this.polylines = const {},
    this.onMapTap,
    this.onCameraIdle,
    this.onCameraMove,
    this.onMapCreated,
    this.onMapReady,
  });

  @override
  State<NativePlatformMap> createState() => _NativePlatformMapState();
}

class _NativePlatformMapState extends State<NativePlatformMap> {
  NativeMapController? _controller;

  Map<String, dynamic> get _creationParams => {
        'initialLat': widget.initialCenter.latitude,
        'initialLng': widget.initialCenter.longitude,
        'initialZoom': widget.initialZoom,
        'darkMode': widget.darkMode,
        'showTraffic': widget.showTraffic,
        if (widget.mapStyle != null) 'mapStyle': widget.mapStyle,
      };

  void _onPlatformViewCreated(int viewId) {
    final ctrl = NativeMapController(viewId);
    _controller = ctrl;

    MethodChannel('com.swiftride.app/native_map_view_$viewId')
        .setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMapReady':
          widget.onMapReady?.call();
          if (widget.markers.isNotEmpty) {
            ctrl.setMarkers(widget.markers);
          }
          if (widget.polylines.isNotEmpty) {
            ctrl.setPolylines(widget.polylines);
          }
          break;
        case 'onMapTap':
          final lat = (call.arguments as Map)['latitude'] as double?;
          final lng = (call.arguments as Map)['longitude'] as double?;
          if (lat != null && lng != null) {
            widget.onMapTap?.call(LatLng(lat, lng));
          }
          break;
        case 'onCameraIdle':
          final lat = (call.arguments as Map)['latitude'] as double?;
          final lng = (call.arguments as Map)['longitude'] as double?;
          if (lat != null && lng != null) {
            widget.onCameraIdle?.call(LatLng(lat, lng));
          }
          break;
        case 'onCameraMove':
          final lat = (call.arguments as Map)['latitude'] as double?;
          final lng = (call.arguments as Map)['longitude'] as double?;
          if (lat != null && lng != null) {
            widget.onCameraMove?.call(LatLng(lat, lng));
          }
          break;
      }
    });

    widget.onMapCreated?.call(ctrl);
  }

  @override
  void didUpdateWidget(NativePlatformMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null) {
      if (oldWidget.markers != widget.markers) {
        _controller!.setMarkers(widget.markers);
      }
      if (oldWidget.polylines != widget.polylines) {
        _controller!.setPolylines(widget.polylines);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const viewType = 'com.swiftride.app/native_map_view';

    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: _creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
            ..create();
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: _creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else {
      return const Center(child: Text('Map View'));
    }
  }
}
