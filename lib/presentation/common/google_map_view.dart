import 'package:flutter/material.dart';
import 'native_platform_map.dart';
import 'real_map_view.dart';

export '../../services/native_map_service.dart';
export 'native_platform_map.dart';
export 'real_map_view.dart';

/// Backward-compatible wrapper delegating to native [RealMapView].
class GoogleMapView extends StatelessWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final MapMode mode;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final ValueChanged<LatLng>? onPinChanged;
  final ValueChanged<LatLng>? onCameraIdle;
  final ValueChanged<LatLng>? onMapTap;
  final bool showMyLocationButton;
  final bool showTraffic;
  final bool darkMode;
  final VoidCallback? onMapReady;
  final void Function(GoogleMapController controller)? onControllerCreated;

  /// Screen-reader description of what the map shows.
  final String? semanticsLabel;

  const GoogleMapView({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15,
    this.mode = MapMode.viewOnly,
    this.markers = const {},
    this.polylines = const {},
    this.circles = const {},
    this.onPinChanged,
    this.onCameraIdle,
    this.onMapTap,
    this.showMyLocationButton = true,
    this.showTraffic = false,
    this.darkMode = false,
    this.onMapReady,
    this.onControllerCreated,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return RealMapView(
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      mode: mode,
      markers: markers,
      polylines: polylines,
      circles: circles,
      onPinChanged: onPinChanged,
      onCameraIdle: onCameraIdle,
      onMapTap: onMapTap,
      showMyLocationButton: showMyLocationButton,
      showTraffic: showTraffic,
      darkMode: darkMode,
      onMapReady: onMapReady,
      onControllerCreated: onControllerCreated,
      semanticsLabel: semanticsLabel,
    );
  }
}

/// Drop-in compatibility widget embedding native Google Maps (AndroidView / UiKitView).
class GoogleMap extends StatelessWidget {
  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<LatLng>? onCameraMove;
  final VoidCallback? onCameraIdle;
  final ValueChanged<GoogleMapController>? onMapCreated;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool trafficEnabled;
  final String? style;
  final EdgeInsets padding;
  final bool compassEnabled;
  final bool mapToolbarEnabled;
  final bool zoomControlsEnabled;
  final bool buildingsEnabled;

  const GoogleMap({
    super.key,
    required this.initialCameraPosition,
    this.markers = const {},
    this.polylines = const {},
    this.circles = const {},
    this.onTap,
    this.onCameraMove,
    this.onCameraIdle,
    this.onMapCreated,
    this.myLocationEnabled = true,
    this.myLocationButtonEnabled = false,
    this.trafficEnabled = false,
    this.style,
    this.padding = EdgeInsets.zero,
    this.compassEnabled = false,
    this.mapToolbarEnabled = false,
    this.zoomControlsEnabled = false,
    this.buildingsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return NativePlatformMap(
      initialCenter: initialCameraPosition.target,
      initialZoom: initialCameraPosition.zoom,
      darkMode: Theme.of(context).brightness == Brightness.dark,
      showTraffic: trafficEnabled,
      mapStyle: style,
      markers: markers,
      polylines: polylines,
      onMapTap: onTap,
      onCameraIdle: onCameraIdle != null ? (_) => onCameraIdle!() : null,
      onCameraMove: onCameraMove,
      onMapCreated: onMapCreated,
    );
  }
}
