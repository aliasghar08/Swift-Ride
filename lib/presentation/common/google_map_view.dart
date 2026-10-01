import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/map_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Reusable Google Maps wrapper used by both rider and driver apps.
///
/// Modes:
/// - [MapMode.viewOnly]        — just renders markers/polylines, no drag pin
/// - [MapMode.pinPicker]       — draggable center pin for pickup/dropoff selection
/// - [MapMode.navigation]      — follows user location with heading
/// - [MapMode.liveTracking]    — follows a moving driver marker
enum MapMode { viewOnly, pinPicker, navigation, liveTracking }

class GoogleMapView extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final MapMode mode;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;

  /// Fires when user drops or drags a pin (pin-picker mode, debounced 350ms).
  final ValueChanged<LatLng>? onPinChanged;

  /// Fires when the camera settles. Use for reverse geocoding.
  final ValueChanged<LatLng>? onCameraIdle;

  /// Fires on map tap.
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
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  GoogleMapController? _controller;
  LatLng _centerPin = const LatLng(37.7749, -122.4194);
  bool _cameraMoving = false;
  Timer? _debounce;
  bool _isLocating = false;

  static const _darkMapStyle = '''
  [
    {"elementType": "geometry","stylers": [{"color": "#0B1120"}]},
    {"elementType": "labels.text.fill","stylers": [{"color": "#8899AA"}]},
    {"elementType": "labels.text.stroke","stylers": [{"color": "#0B1120"}]},
    {"featureType": "road","elementType": "geometry","stylers": [{"color": "#1E2A3A"}]},
    {"featureType": "water","elementType": "geometry","stylers": [{"color": "#0A1628"}]}
  ]
  ''';

  @override
  void initState() {
    super.initState();
    _centerPin = widget.initialCenter;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _controller = controller;
    widget.onControllerCreated?.call(controller);
    widget.onMapReady?.call();
  }

  void _onCameraMove(CameraPosition pos) {
    _cameraMoving = true;
    _centerPin = pos.target;
    if (widget.mode == MapMode.pinPicker) {
      // Reverse-geocode debounce: only fire after user stops moving
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) {
          widget.onPinChanged?.call(_centerPin);
        }
      });
    }
  }

  void _onCameraIdle() {
    if (_cameraMoving) {
      _cameraMoving = false;
      widget.onCameraIdle?.call(_centerPin);
    }
  }

  Future<void> _moveToCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final target = await MapService().getCurrentPosition();
      _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 16.0),
        ),
      );

      if (widget.mode == MapMode.pinPicker) {
        widget.onPinChanged?.call(target);
      }
    } catch (e) {
      debugPrint('Failed to locate device: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          style: widget.darkMode ? _darkMapStyle : null,
          initialCameraPosition: CameraPosition(
            target: widget.initialCenter,
            zoom: widget.initialZoom,
          ),
          onMapCreated: _onMapCreated,
          onCameraMove: widget.mode == MapMode.pinPicker ? _onCameraMove : null,
          onCameraIdle: _onCameraIdle,
          onTap: widget.onMapTap,
          markers: widget.markers,
          polylines: widget.polylines,
          circles: widget.circles,
          myLocationEnabled: widget.mode != MapMode.viewOnly,
          myLocationButtonEnabled: false, // We render our own themed FAB
          compassEnabled: widget.mode == MapMode.navigation,
          trafficEnabled: widget.showTraffic,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          buildingsEnabled: true,
          indoorViewEnabled: false,
        ),

        // Center pin for pin-picker mode
        if (widget.mode == MapMode.pinPicker)
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 40), // Pin tip at center coordinate
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_pin, size: 48, color: Colors.redAccent),
                    SizedBox(height: 2),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(width: 8, height: 4),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Custom locate-me FAB
        if (widget.showMyLocationButton)
          Positioned(
            right: 16,
            bottom: 96,
            child: FloatingActionButton.small(
              heroTag: 'map_locate_${widget.mode.name}_${widget.initialCenter.latitude}',
              onPressed: _isLocating ? null : _moveToCurrentLocation,
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                    )
                  : const Icon(Icons.my_location, size: 20),
            ),
          ),
      ],
    );
  }
}
