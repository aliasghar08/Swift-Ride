import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/map_service.dart';
import 'glass_container.dart';

/// Supported operation modes for the map view.
enum MapMode { viewOnly, pinPicker, navigation, liveTracking }

/// State-of-the-art Dual-Engine Map View for SwiftRide.
///
/// Features:
/// 1. **Live Cartography Engine** (via OpenStreetMap / CartoDB): Renders 100% real streets,
///    labels, sectors (G-9, F-8, Blue Area, Islamabad Airport), and buildings immediately
///    with zero API keys or billing required.
/// 2. **Google Maps SDK Engine**: Uses native GMSMapView when configured with a valid Google Cloud API key.
/// 3. Seamless one-tap toggle between engines for development, testing, and production.
class RealMapView extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final MapMode mode;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;

  /// Fires when user drops or drags a pin (pin-picker mode, debounced 350ms).
  final ValueChanged<LatLng>? onPinChanged;

  /// Fires when the camera settles.
  final ValueChanged<LatLng>? onCameraIdle;

  /// Fires on map tap.
  final ValueChanged<LatLng>? onMapTap;

  final bool showMyLocationButton;
  final bool showTraffic;
  final bool darkMode;
  final VoidCallback? onMapReady;
  final void Function(GoogleMapController controller)? onMapCreated;
  final void Function(GoogleMapController controller)? onControllerCreated;

  const RealMapView({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14.5,
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
    this.onMapCreated,
    this.onControllerCreated,
  });

  @override
  State<RealMapView> createState() => _RealMapViewState();
}

class _RealMapViewState extends State<RealMapView> {
  // Engine switch: defaults to Cartography engine (OSM/CartoDB) to guarantee real visible tiles
  bool _useGoogleMaps = false;

  // Google Maps Controller
  GoogleMapController? _googleMapController;

  // Flutter Map Controller
  final fmap.MapController _flutterMapController = fmap.MapController();

  LatLng _currentCenter = const LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
  bool _cameraMoving = false;
  Timer? _debounce;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialCenter;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _googleMapController?.dispose();
    super.dispose();
  }

  void _onPositionChanged(ll.LatLng center, bool hasGesture) {
    if (!hasGesture && widget.mode != MapMode.pinPicker) return;
    _cameraMoving = true;
    _currentCenter = LatLng(center.latitude, center.longitude);

    if (widget.mode == MapMode.pinPicker) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) {
          widget.onPinChanged?.call(_currentCenter);
        }
      });
    }
  }

  void _onCameraIdle() {
    if (_cameraMoving) {
      _cameraMoving = false;
      widget.onCameraIdle?.call(_currentCenter);
    }
  }

  Future<void> _moveToCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final target = await MapService().getCurrentPosition();
      _currentCenter = target;

      if (_useGoogleMaps && _googleMapController != null) {
        _googleMapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 16.0),
          ),
        );
      } else {
        _flutterMapController.move(
          ll.LatLng(target.latitude, target.longitude),
          16.0,
        );
      }

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
    final isDark = widget.darkMode || Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // 1. Primary Map Engine
        Positioned.fill(
          child: _useGoogleMaps
              ? _buildGoogleMapsEngine(isDark)
              : _buildCartographyEngine(isDark),
        ),

        // 2. Center Pin in Pin-Picker Mode
        if (widget.mode == MapMode.pinPicker)
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 42),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_pin, size: 50, color: Colors.redAccent),
                    SizedBox(height: 2),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(width: 10, height: 5),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 3. Floating Engine Switcher Badge (Top-Right under status bar)
        Positioned(
          top: 108,
          right: 14,
          child: SafeArea(
            child: GlassContainer(
              isDark: isDark,
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              borderColor: AppTheme.accentCyan.withValues(alpha: 0.4),
              child: InkWell(
                onTap: () {
                  setState(() => _useGoogleMaps = !_useGoogleMaps);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      backgroundColor: AppTheme.primaryNavy,
                      content: Text(
                        _useGoogleMaps
                            ? 'Switched to Google Maps SDK (Requires GMSApiKey in Info.plist)'
                            : 'Switched to Real Cartography Engine (100% Visible Tiles)',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _useGoogleMaps ? Icons.public : Icons.map_outlined,
                      size: 15,
                      color: _useGoogleMaps ? Colors.amberAccent : AppTheme.accentCyan,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _useGoogleMaps ? 'Google Maps' : 'Live Cartography',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.primaryNavy,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(Icons.sync_alt, size: 12, color: Colors.white60),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 4. Locate-Me FAB
        if (widget.showMyLocationButton)
          Positioned(
            right: 16,
            bottom: 100,
            child: FloatingActionButton.small(
              heroTag: 'real_map_locate_${widget.mode.name}_${widget.initialCenter.latitude}',
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

  // --- Real OpenStreetMap / CartoDB Engine (Zero API Key Needed) ---
  Widget _buildCartographyEngine(bool isDark) {
    // High-resolution Retina map tiles with clear street names and sector markers
    final tileUrl = isDark
        ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
        : 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';

    // Convert markers to flutter_map markers
    final convertedMarkers = widget.markers.map((m) {
      return fmap.Marker(
        point: ll.LatLng(m.position.latitude, m.position.longitude),
        width: 44,
        height: 44,
        child: _buildMarkerWidget(m),
      );
    }).toList();

    // Convert polylines to flutter_map polylines
    final convertedPolylines = widget.polylines.map((p) {
      return fmap.Polyline(
        points: p.points.map((pt) => ll.LatLng(pt.latitude, pt.longitude)).toList(),
        color: p.color,
        strokeWidth: p.width.toDouble().clamp(3.0, 7.0),
      );
    }).toList();

    // Convert circles
    final convertedCircles = widget.circles.map((c) {
      return fmap.CircleMarker(
        point: ll.LatLng(c.center.latitude, c.center.longitude),
        radius: c.radius.toDouble(),
        useRadiusInMeter: true,
        color: c.fillColor,
        borderColor: c.strokeColor,
        borderStrokeWidth: c.strokeWidth.toDouble(),
      );
    }).toList();

    return fmap.FlutterMap(
      mapController: _flutterMapController,
      options: fmap.MapOptions(
        initialCenter: ll.LatLng(widget.initialCenter.latitude, widget.initialCenter.longitude),
        initialZoom: widget.initialZoom,
        onTap: (tapPosition, point) {
          widget.onMapTap?.call(LatLng(point.latitude, point.longitude));
        },
        onPositionChanged: (camera, hasGesture) {
          _onPositionChanged(camera.center, hasGesture);
        },
        onMapReady: widget.onMapReady,
        interactionOptions: const fmap.InteractionOptions(
          flags: fmap.InteractiveFlag.all,
        ),
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.dartnexuslab.swiftri',
          subdomains: const ['a', 'b', 'c', 'd'],
          maxZoom: 20,
        ),
        if (convertedCircles.isNotEmpty)
          fmap.CircleLayer(circles: convertedCircles),
        if (convertedPolylines.isNotEmpty)
          fmap.PolylineLayer(polylines: convertedPolylines),
        if (convertedMarkers.isNotEmpty)
          fmap.MarkerLayer(markers: convertedMarkers),
      ],
    );
  }

  Widget _buildMarkerWidget(Marker marker) {
    final id = marker.markerId.value.toLowerCase();
    if (id.contains('pickup')) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, color: Colors.greenAccent, size: 36),
          CircleAvatar(radius: 3, backgroundColor: Colors.white),
        ],
      );
    }
    if (id.contains('dropoff')) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, color: Colors.redAccent, size: 36),
          CircleAvatar(radius: 3, backgroundColor: Colors.white),
        ],
      );
    }
    if (id.contains('driver')) {
      return Transform.rotate(
        angle: marker.rotation * (3.141592653589793 / 180),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: AppTheme.accentCyan,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          child: const Icon(Icons.navigation, color: AppTheme.primaryNavy, size: 20),
        ),
      );
    }
    return const Icon(Icons.location_pin, color: Colors.blueAccent, size: 34);
  }

  // --- Official Google Maps Engine (Uses GMSMapView) ---
  Widget _buildGoogleMapsEngine(bool isDark) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialCenter,
        zoom: widget.initialZoom,
      ),
      onMapCreated: (c) {
        _googleMapController = c;
        widget.onMapCreated?.call(c);
        widget.onControllerCreated?.call(c);
        widget.onMapReady?.call();
      },
      onCameraMove: (pos) => _onPositionChanged(
        ll.LatLng(pos.target.latitude, pos.target.longitude),
        true,
      ),
      onCameraIdle: _onCameraIdle,
      onTap: widget.onMapTap,
      markers: widget.markers,
      polylines: widget.polylines,
      circles: widget.circles,
      myLocationEnabled: widget.mode != MapMode.viewOnly,
      myLocationButtonEnabled: false,
      compassEnabled: true,
      trafficEnabled: widget.showTraffic,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      buildingsEnabled: true,
    );
  }
}
