import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/map_service.dart';
import 'glass_container.dart';
import 'map_marker_icons.dart';

/// Supported operation modes for the map view.
enum MapMode { viewOnly, pinPicker, navigation, liveTracking }

/// State-of-the-art Dual-Engine Map View for SwiftRide.
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

  /// Inset used so map content is not hidden behind top/bottom chrome.
  final EdgeInsets mapPadding;

  /// Screen-reader description of what this map is showing.
  final String? semanticsLabel;

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
    this.mapPadding = const EdgeInsets.only(top: 150, bottom: 260),
    this.semanticsLabel,
  });

  @override
  State<RealMapView> createState() => _RealMapViewState();
}

class _RealMapViewState extends State<RealMapView> {
  bool _useGoogleMaps =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      kIsWeb;

  /// Uber-style clean map: muted land, white roads, no POI clutter.
  static const String _uberLightStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f5f5f5"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#e5efe0"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.arterial","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#dadada"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9d6e3"}]}
]''';

  /// Uber-style night map.
  static const String _uberDarkStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#1d2330"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a93a6"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1d2330"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c3445"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3b4559"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]}
]''';

  void _fitGoogleBounds() {
    final c = _googleMapController;
    if (c == null || widget.markers.length < 2) return;
    final pts = widget.markers.map((m) => m.position).toList();
    double minLat = pts.first.latitude, maxLat = minLat;
    double minLng = pts.first.longitude, maxLng = minLng;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant RealMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_useGoogleMaps) return;
    if (widget.mode == MapMode.pinPicker || widget.mode == MapMode.navigation)
      return;

    final lastPan = _lastUserPan;
    if (lastPan != null &&
        DateTime.now().difference(lastPan) < _autoFitCooldown) {
      return;
    }

    final changed = !setEquals(
      oldWidget.markers.map((m) => m.position).toSet(),
      widget.markers.map((m) => m.position).toSet(),
    );
    if (!changed) return;

    final hadRoute = oldWidget.polylines.isNotEmpty;
    final hasRoute = widget.polylines.isNotEmpty;
    final routeChanged =
        hadRoute != hasRoute ||
        (hasRoute &&
            oldWidget.polylines.first.points.length !=
                widget.polylines.first.points.length);

    if (routeChanged || widget.markers.length <= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitGoogleBounds();
      });
    }
  }

  void followHeading(double heading, {double zoom = 17, double tilt = 50}) {
    final c = _googleMapController;
    if (c == null || !_useGoogleMaps) return;
    c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentCenter,
          zoom: zoom,
          tilt: tilt,
          bearing: heading,
        ),
      ),
    );
  }

  GoogleMapController? _googleMapController;
  final fmap.MapController _flutterMapController = fmap.MapController();

  LatLng _currentCenter = const LatLng(
    AppConstants.defaultLat,
    AppConstants.defaultLng,
  );
  bool _cameraMoving = false;
  Timer? _debounce;
  bool _isLocating = false;

  static int _instanceSeq = 0;
  late final String _locateHeroTag = 'swiftride_locate_${_instanceSeq++}';

  DateTime? _lastUserPan;
  static const Duration _autoFitCooldown = Duration(seconds: 10);
  bool _userTouching = false;

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialCenter;

    MapMarkerIcons.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
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
    if (hasGesture) _lastUserPan = DateTime.now();

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

      if (target == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'We could not get your location. Check that location access is '
                'allowed and that GPS is on, then try again.',
              ),
              backgroundColor: AppTheme.sunsetCoral,
            ),
          );
        }
        return;
      }

      _currentCenter = target;

      final zoom = _useGoogleMaps && _googleMapController != null
          ? await _googleMapController!.getZoomLevel()
          : _flutterMapController.camera.zoom;
      final targetZoom = zoom < 16.0 ? 16.0 : zoom;

      if (_useGoogleMaps && _googleMapController != null) {
        _googleMapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: targetZoom),
          ),
        );
      } else {
        _flutterMapController.move(
          ll.LatLng(target.latitude, target.longitude),
          targetZoom,
        );
      }

      if (widget.mode == MapMode.pinPicker) {
        widget.onPinChanged?.call(target);
      }
    } catch (e) {
      debugPrint('Failed to locate device: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('We could not get your location. Please try again.'),
            backgroundColor: AppTheme.sunsetCoral,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.darkMode || Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);

    return Stack(
      children: [
        // 1. Primary Map Engine
        Positioned.fill(
          child: Semantics(
            container: true,
            label:
                widget.semanticsLabel ??
                (widget.markers.isEmpty
                    ? 'Map'
                    : 'Map showing ${widget.markers.length} locations'),
            child: _useGoogleMaps
                ? _buildGoogleMapsEngine(isDark)
                : _buildCartographyEngine(isDark),
          ),
        ),

        // 2. Compact Center Pin in Pin-Picker Mode
        if (widget.mode == MapMode.pinPicker)
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -18),
                child: const Icon(
                  Icons.location_pin,
                  size: 38,
                  color: AppTheme.sunsetCoral,
                ),
              ),
            ),
          ),

        // 3. Floating Engine Switcher Badge (Debug Only)
        if (kDebugMode)
          Positioned(
            top: 108,
            right: 14,
            child: SafeArea(
              child: GlassContainer(
                isDark: isDark,
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
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
                          _useGoogleMaps ? 'Switched to Google Maps SDK' : 'Switched to Real Cartography Engine (100% Visible Tiles)',
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
                        color: _useGoogleMaps
                            ? Colors.amberAccent
                            : AppTheme.accentCyan,
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
                      const Icon(
                        Icons.sync_alt,
                        size: 12,
                        color: Colors.white60,
                      ),
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
              heroTag: _locateHeroTag,
              onPressed: _isLocating ? null : _moveToCurrentLocation,
              backgroundColor: c.mapChromeStrong,
              foregroundColor: Colors.white,
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.cyanAccent,
                      ),
                    )
                  : const Icon(Icons.my_location, size: 20),
            ),
          ),
      ],
    );
  }

  Widget _buildCartographyEngine(bool isDark) {
    final tileUrl = isDark
        ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
        : 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';

    final convertedMarkers = widget.markers.map((m) {
      return fmap.Marker(
        point: ll.LatLng(m.position.latitude, m.position.longitude),
        width: 44,
        height: 44,
        child: _buildMarkerWidget(m),
      );
    }).toList();

    final convertedPolylines = widget.polylines.map((p) {
      return fmap.Polyline(
        points: p.points
            .map((pt) => ll.LatLng(pt.latitude, pt.longitude))
            .toList(),
        color: p.color,
        strokeWidth: p.width.toDouble().clamp(3.0, 7.0),
      );
    }).toList();

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
        initialCenter: ll.LatLng(
          widget.initialCenter.latitude,
          widget.initialCenter.longitude,
        ),
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
          userAgentPackageName: 'com.dartnexuslab.swiftride',
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
          child: const Icon(
            Icons.navigation,
            color: AppTheme.primaryNavy,
            size: 20,
          ),
        ),
      );
    }
    return const Icon(Icons.location_pin, color: Colors.blueAccent, size: 34);
  }

  Widget _buildGoogleMapsEngine(bool isDark) {
    final padding = widget.mode == MapMode.pinPicker
        ? EdgeInsets.zero
        : widget.mapPadding;
    final navigating = widget.mode == MapMode.navigation;

    return Listener(
      onPointerDown: (_) => _userTouching = true,
      onPointerUp: (_) => _userTouching = false,
      onPointerCancel: (_) => _userTouching = false,
      child: GoogleMap(
        style: isDark ? _uberDarkStyle : _uberLightStyle,
        padding: padding,
        initialCameraPosition: CameraPosition(
          target: widget.initialCenter,
          zoom: widget.initialZoom,
          tilt: navigating ? 50 : 0,
        ),
        onMapCreated: (c) {
          _googleMapController = c;
          widget.onMapCreated?.call(c);
          widget.onControllerCreated?.call(c);
          widget.onMapReady?.call();
          if (widget.mode != MapMode.pinPicker && !navigating) {
            Future.delayed(const Duration(milliseconds: 400), _fitGoogleBounds);
          }
        },
        onCameraMove: (pos) => _onPositionChanged(
          ll.LatLng(pos.target.latitude, pos.target.longitude),
          _userTouching,
        ),
        onCameraIdle: _onCameraIdle,
        onTap: widget.onMapTap,
        markers: widget.markers,
        polylines: widget.polylines,
        circles: widget.circles,
        // Always enable native Google location blue puck
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        compassEnabled: navigating,
        trafficEnabled: widget.showTraffic,
        mapToolbarEnabled: false,
        zoomControlsEnabled: false,
        buildingsEnabled: true,
      ),
    );
  }
}
