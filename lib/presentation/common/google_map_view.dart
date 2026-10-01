import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'real_map_view.dart';

export 'real_map_view.dart';

/// Backward-compatible wrapper delegating to Dual-Engine [RealMapView].
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
    );
  }
}
