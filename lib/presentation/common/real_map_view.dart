import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/map_service.dart';
import 'map_marker_icons.dart';
import 'native_platform_map.dart';

/// Supported operation modes for the map view.
enum MapMode { viewOnly, pinPicker, navigation, liveTracking }

/// High-performance Native Map View for SwiftRide using Kotlin (Android) & Swift (iOS).
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

  final bool showCenterPin;
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
    this.showCenterPin = true,
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

  void _fitBounds() {
    final c = _controller;
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

    if (widget.mode == MapMode.pinPicker || widget.mode == MapMode.navigation) {
      return;
    }

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
        if (mounted) _fitBounds();
      });
    }
  }

  void followHeading(double heading, {double zoom = 17, double tilt = 50}) {
    final c = _controller;
    if (c == null) return;
    c.animateCamera(
      CameraPosition(
        target: _currentCenter,
        zoom: zoom,
        tilt: tilt,
        bearing: heading,
      ),
    );
  }

  NativeMapController? _controller;
  LatLng _currentCenter = const LatLng(
    AppConstants.defaultLat,
    AppConstants.defaultLng,
  );
  Timer? _debounce;
  bool _isLocating = false;

  static int _instanceSeq = 0;
  late final String _locateHeroTag = 'swiftride_locate_${_instanceSeq++}';

  DateTime? _lastUserPan;
  static const Duration _autoFitCooldown = Duration(seconds: 10);

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
    _controller?.dispose();
    super.dispose();
  }

  void _onPositionChanged(LatLng center, bool hasGesture) {
    if (!hasGesture && widget.mode != MapMode.pinPicker) return;
    _currentCenter = center;
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

  void _onCameraIdle(LatLng center) {
    _currentCenter = center;
    widget.onCameraIdle?.call(_currentCenter);
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

      if (_controller != null) {
        await _controller!.animateCamera(target, zoom: 16.5);
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
        // 1. Primary Native Platform Map View (AndroidView on Android, UiKitView on iOS)
        Positioned.fill(
          child: Semantics(
            container: true,
            label: widget.semanticsLabel ??
                (widget.markers.isEmpty
                    ? 'Map'
                    : 'Map showing ${widget.markers.length} locations'),
            child: NativePlatformMap(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              darkMode: isDark,
              showTraffic: widget.showTraffic,
              mapStyle: isDark ? _uberDarkStyle : _uberLightStyle,
              markers: widget.markers,
              polylines: widget.polylines,
              onMapTap: widget.onMapTap,
              onCameraIdle: _onCameraIdle,
              onCameraMove: (pos) => _onPositionChanged(pos, true),
              onMapCreated: (ctrl) {
                _controller = ctrl;
                widget.onMapCreated?.call(ctrl);
                widget.onControllerCreated?.call(ctrl);
                if (widget.mode != MapMode.pinPicker &&
                    widget.mode != MapMode.navigation) {
                  Future.delayed(
                      const Duration(milliseconds: 400), _fitBounds);
                }
              },
              onMapReady: widget.onMapReady,
            ),
          ),
        ),

        // 2. Center Pin in Pin-Picker Mode
        if (widget.mode == MapMode.pinPicker && widget.showCenterPin)
          IgnorePointer(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Ground contact target ring
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.sunsetCoral.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_pin,
                            size: 44,
                            color: AppTheme.sunsetCoral,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 3. Locate-Me FAB
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
}
