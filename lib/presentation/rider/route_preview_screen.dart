import 'package:flutter/material.dart';

import '../../domain/models/location_point_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/map_service.dart';
import '../common/google_map_view.dart';
import '../common/map_markers.dart';
import '../view_models/rider_view_model.dart';

class RoutePreviewScreen extends StatefulWidget {
  final RiderViewModel? viewModel;
  final LocationPoint? explicitPickup;
  final LocationPoint? explicitDropoff;
  final List<RouteOption>? explicitRoutes;
  final int initialRouteIndex;

  const RoutePreviewScreen({
    super.key,
    this.viewModel,
    this.explicitPickup,
    this.explicitDropoff,
    this.explicitRoutes,
    this.initialRouteIndex = 0,
  }) : assert(
          viewModel != null || explicitRoutes != null,
          'Either viewModel or explicitRoutes must be provided',
        );

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  GoogleMapController? _mapController;
  late int _selectedRouteIndex;
  int? _selectedStepIndex;

  LocationPoint? get _pickup =>
      widget.viewModel?.pickupLocation ?? widget.explicitPickup;
  LocationPoint? get _dropoff =>
      widget.viewModel?.dropoffLocation ?? widget.explicitDropoff;
  List<RouteOption> get _routes =>
      widget.viewModel?.routes ?? widget.explicitRoutes ?? const [];

  @override
  void initState() {
    super.initState();
    MapMarkers.ensureOriginDot();
    _selectedRouteIndex =
        widget.viewModel?.selectedRouteIndex ?? widget.initialRouteIndex;
  }

  void _selectRoute(int index) {
    if (index == _selectedRouteIndex) return;
    setState(() {
      _selectedRouteIndex = index;
      _selectedStepIndex = null;
      widget.viewModel?.selectRoute(index);
    });
    final routes = _routes;
    if (routes.isNotEmpty && index < routes.length) {
      _fitRoute(routes[index]);
    }
  }

  void _fitRoute(RouteOption route) {
    final points = route.polylinePoints;
    if (points.isEmpty || _mapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 70),
    );
  }

  void _focusStep(int stepIndex, RouteOption route) {
    if (stepIndex < 0 || stepIndex >= route.steps.length) return;
    setState(() {
      _selectedStepIndex = stepIndex;
    });

    final step = route.steps[stepIndex];
    LatLng? targetLoc = step.startLocation;

    if (targetLoc == null && step.stepPoints.isNotEmpty) {
      targetLoc = step.stepPoints.first;
    }

    if (targetLoc == null && route.polylinePoints.isNotEmpty) {
      final ratio = stepIndex / route.steps.length;
      final idx = ((route.polylinePoints.length - 1) * ratio).round();
      targetLoc = route.polylinePoints[idx];
    }

    if (targetLoc != null && _mapController != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: targetLoc,
            zoom: 16.5,
            tilt: 30,
          ),
        ),
      );
    }
  }

  static IconData _maneuverIcon(String maneuver) {
    switch (maneuver.toUpperCase()) {
      case 'TURN_LEFT':
        return Icons.turn_left;
      case 'TURN_SLIGHT_LEFT':
        return Icons.turn_slight_left;
      case 'TURN_SHARP_LEFT':
        return Icons.turn_sharp_left;
      case 'TURN_RIGHT':
        return Icons.turn_right;
      case 'TURN_SLIGHT_RIGHT':
        return Icons.turn_slight_right;
      case 'TURN_SHARP_RIGHT':
        return Icons.turn_sharp_right;
      case 'U_TURN_LEFT':
      case 'U_TURN_RIGHT':
      case 'U_TURN':
        return Icons.u_turn_left;
      case 'STRAIGHT':
        return Icons.straight;
      case 'ROUNDABOUT_LEFT':
      case 'ROUNDABOUT_RIGHT':
      case 'ROUNDABOUT_ENTER':
      case 'ROUNDABOUT_EXIT':
        return Icons.roundabout_left;
      case 'MERGE':
        return Icons.merge;
      case 'FORK_LEFT':
        return Icons.fork_left;
      case 'FORK_RIGHT':
        return Icons.fork_right;
      case 'RAMP_LEFT':
        return Icons.ramp_left;
      case 'RAMP_RIGHT':
        return Icons.ramp_right;
      case 'NAME_CHANGE':
        return Icons.alt_route;
      case 'DEPART':
        return Icons.navigation;
      case 'DESTINATION':
        return Icons.place;
      default:
        return Icons.navigation;
    }
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static String _formatDurationDetailed(double min) {
    if (min >= 60) {
      final hours = min ~/ 60;
      final remainingMins = (min % 60).round();
      if (remainingMins == 0) return '$hours hr';
      return '$hours hr $remainingMins min';
    }
    return '${min.round()} min';
  }

  static Color _trafficColour(TrafficInterval? interval) {
    if (interval == null) return AppTheme.accentCyan;
    if (interval.isJam) return AppTheme.sunsetCoral;
    if (interval.isSlow) return AppTheme.amberWarning;
    return AppTheme.accentCyan;
  }

  Set<Polyline> _buildPolylines() {
    final routes = _routes;
    if (routes.isEmpty) return const {};

    const casingWidth = 15;
    const fillWidth = 10;

    final set = <Polyline>{};

    // Unselected routes
    for (var i = 0; i < routes.length; i++) {
      if (i != _selectedRouteIndex) {
        set.add(
          Polyline(
            polylineId: PolylineId('preview_route_$i'),
            points: routes[i].polylinePoints,
            color: const Color(0xFF94A3B8).withValues(alpha: 0.65),
            width: 7,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            geodesic: true,
            zIndex: -1,
          ),
        );
      }
    }

    // Selected route
    if (_selectedRouteIndex < routes.length) {
      final sel = routes[_selectedRouteIndex];
      set.add(
        Polyline(
          polylineId: PolylineId('preview_route_${_selectedRouteIndex}_casing'),
          points: sel.polylinePoints,
          color: AppTheme.darkNavy,
          width: casingWidth,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          geodesic: true,
          zIndex: 0,
        ),
      );
      set.add(
        Polyline(
          polylineId: PolylineId('preview_route_${_selectedRouteIndex}_fill'),
          points: sel.polylinePoints,
          color: AppTheme.accentCyan,
          width: fillWidth,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          geodesic: true,
          zIndex: 1,
        ),
      );

      final segs = TrafficInterval.segment(
        sel.polylinePoints,
        sel.trafficIntervals,
      );
      for (var k = 0; k < segs.length; k++) {
        set.add(
          Polyline(
            polylineId: PolylineId(
              'preview_route_${_selectedRouteIndex}_traffic_$k',
            ),
            points: segs[k].points,
            color: _trafficColour(segs[k].interval),
            width: fillWidth,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            geodesic: true,
            zIndex: 2,
          ),
        );
      }

      // If a specific step is selected, highlight its micro-polyline in bright amber/white
      if (_selectedStepIndex != null && _selectedStepIndex! < sel.steps.length) {
        final step = sel.steps[_selectedStepIndex!];
        final pts = step.stepPoints;
        if (pts.length >= 2) {
          set.add(
            Polyline(
              polylineId: const PolylineId('preview_selected_step_highlight'),
              points: pts,
              color: AppTheme.amberWarning,
              width: 13,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              zIndex: 10,
            ),
          );
        }
      }
    }

    return set;
  }

  Set<Marker> _buildMarkers() {
    final pickup = _pickup;
    final dropoff = _dropoff;
    final routes = _routes;
    final hasRoute = routes.isNotEmpty && _selectedRouteIndex < routes.length;
    final selected = hasRoute ? routes[_selectedRouteIndex] : null;

    final markers = <Marker>{
      if (pickup != null)
        MapMarkers.originDot(
          LatLng(pickup.latitude, pickup.longitude),
          id: 'preview_origin_dot',
        ),
      if (dropoff != null)
        MapMarkers.dropoff(
          LatLng(dropoff.latitude, dropoff.longitude),
          id: 'preview_dropoff_pin',
        ),
    };

    // If a step is highlighted, place a focused maneuver beacon
    if (selected != null &&
        _selectedStepIndex != null &&
        _selectedStepIndex! < selected.steps.length) {
      final step = selected.steps[_selectedStepIndex!];
      final loc = step.startLocation ??
          (step.stepPoints.isNotEmpty ? step.stepPoints.first : null);
      if (loc != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('preview_focused_step_marker'),
            position: loc,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueCyan,
            ),
            infoWindow: InfoWindow(
              title: step.primaryInstruction,
              snippet: step.secondaryInstruction ?? step.distanceText,
            ),
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes;
    final hasRoute = routes.isNotEmpty && _selectedRouteIndex < routes.length;
    final selected = hasRoute ? routes[_selectedRouteIndex] : null;

    final initialCenter = _pickup != null
        ? LatLng(
            _pickup!.latitude,
            _pickup!.longitude,
          )
        : const LatLng(31.5580, 74.3507);

    final now = DateTime.now();
    final departureTimeStr = _formatTime(now);
    final etaTimeStr = selected != null
        ? _formatTime(now.add(Duration(minutes: selected.durationMin.round())))
        : '';

    return Scaffold(
      backgroundColor: AppTheme.primaryNavy,
      body: Stack(
        children: [
          // 1. Full-screen Google Map
          GoogleMapView(
            initialCenter: initialCenter,
            initialZoom: 13,
            mode: MapMode.viewOnly,
            darkMode: true,
            showTraffic: true,
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            onControllerCreated: (ctrl) {
              _mapController = ctrl;
              if (selected != null) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _fitRoute(selected);
                });
              }
            },
          ),

          // 2. Draggable Google Maps Fidelity Directions Sheet
          DraggableScrollableSheet(
            initialChildSize: 0.60,
            minChildSize: 0.22,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.97),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 20,
                      offset: Offset(0, -5),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Top Route Overview & ETA
                    if (selected != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      _formatDurationDetailed(selected.durationMin),
                                      style: TextStyle(
                                        color: selected.trafficLevel == 'HEAVY'
                                            ? AppTheme.sunsetCoral
                                            : selected.trafficLevel == 'MODERATE'
                                                ? AppTheme.amberWarning
                                                : AppTheme.accentCyan,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.slateMuted.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${selected.distanceKm.toStringAsFixed(1)} km',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      'ETA $etaTimeStr',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Text(
                                      '· Typical traffic',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    if (selected.summary.isNotEmpty)
                                      Text(
                                        '· via ${selected.summary}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Driver Earns',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'PKR ${selected.economics.driverProfit.round()}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Route Selector Pills Row
                      if (routes.length > 1) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(routes.length, (idx) {
                              final r = routes[idx];
                              final isSelected = idx == _selectedRouteIndex;
                              final label = r.labels.isNotEmpty
                                  ? r.labels.map((l) {
                                      switch (l.toUpperCase()) {
                                        case 'CHEAPEST':
                                          return 'Cheapest';
                                        case 'FASTEST':
                                          return 'Fastest';
                                        case 'BEST_DRIVER':
                                          return 'Best Driver';
                                        default:
                                          return l;
                                      }
                                    }).join(' · ')
                                  : 'Route ${idx + 1}';

                              final isDark =
                                  Theme.of(context).brightness == Brightness.dark;
                              final c = AppColors.of(context);
                              final chipBg = isSelected
                                  ? AppTheme.primaryBlue
                                  : (isDark ? c.surfaceRaised : const Color(0xFFF1F5F9));
                              final isChipBgDark =
                                  ThemeData.estimateBrightnessForColor(chipBg) == Brightness.dark;
                              final chipTextColor = isSelected
                                  ? Colors.white
                                  : (isChipBgDark ? c.textPrimary : const Color(0xFF0F172A));

                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    '$label · ${_formatDurationDetailed(r.durationMin)}',
                                  ),
                                  selected: isSelected,
                                  onSelected: (_) => _selectRoute(idx),
                                  selectedColor: AppTheme.primaryBlue,
                                  backgroundColor: chipBg,
                                  labelStyle: TextStyle(
                                    color: chipTextColor,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  side: BorderSide(
                                    color: isSelected
                                        ? (isDark ? AppTheme.accentCyan : AppTheme.primaryBlue)
                                        : c.border,
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],

                    const Divider(color: Colors.white12, height: 24),

                    // Turn-by-Turn Header & Steps Count
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Step-by-step guidance',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (selected != null)
                          Text(
                            '${selected.steps.length} turns',
                            style: const TextStyle(
                              color: AppTheme.accentCyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 1. Departure Landmark Card (Google Maps Style)
                    _buildDepartureCard(departureTimeStr),

                    if (selected == null || selected.steps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No detailed directions available for this route.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    else
                      // 2. Continuous Vertical Navigation Timeline
                      ...List.generate(selected.steps.length, (idx) {
                        final step = selected.steps[idx];
                        final isFocused = _selectedStepIndex == idx;
                        final isLast = idx == selected.steps.length - 1;

                        return _buildStepItem(
                          step: step,
                          stepIndex: idx,
                          isFocused: isFocused,
                          isLast: isLast,
                          onTap: () => _focusStep(idx, selected),
                        );
                      }),

                    // 3. Destination Arrival Landmark Card (Google Maps Style)
                    _buildArrivalCard(etaTimeStr),

                    const SizedBox(height: 24),

                    // Start Ride Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.navigation, size: 20),
                        label: const Text(
                          'Start Navigation / Ride',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),

          // 3. Top-left Close Button & Route Controls (Always floating on top)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Material(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.90),
                  shape: const CircleBorder(),
                  elevation: 5,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    ),
                  ),
                ),
                if (selected != null)
                  Row(
                    children: [
                      // Step through turns button
                      if (selected.steps.isNotEmpty)
                        Material(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(20),
                          elevation: 4,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              final nextIdx = (_selectedStepIndex == null)
                                  ? 0
                                  : (_selectedStepIndex! + 1) % selected.steps.length;
                              _focusStep(nextIdx, selected);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.turn_right,
                                    color: AppTheme.accentCyan,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedStepIndex == null
                                        ? 'Preview Turns (${selected.steps.length})'
                                        : 'Turn ${_selectedStepIndex! + 1}/${selected.steps.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      // Re-center Full Route Button
                      Material(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.90),
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            setState(() {
                              _selectedStepIndex = null;
                            });
                            _fitRoute(selected);
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.crop_free,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartureCard(String departureTime) {
    final pickup = _pickup;
    final address = pickup?.address ?? 'Your current location';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                border: Border.all(color: const Color(0xFF10B981), width: 2.5),
              ),
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ),
            Container(
              width: 2.5,
              height: 38,
              color: Colors.white24,
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Depart',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      departureTime,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem({
    required RouteStep step,
    required int stepIndex,
    required bool isFocused,
    required bool isLast,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: isFocused
            ? BoxDecoration(
                color: AppTheme.accentCyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.accentCyan.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline connector + maneuver icon
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isFocused
                        ? AppTheme.accentCyan
                        : AppTheme.slateMuted.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: AppTheme.accentCyan.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    _maneuverIcon(step.maneuver),
                    color: isFocused ? AppTheme.primaryNavy : AppTheme.accentCyan,
                    size: 18,
                  ),
                ),
                Container(
                  width: 2.5,
                  height: 48,
                  color: isFocused
                      ? AppTheme.accentCyan.withValues(alpha: 0.7)
                      : Colors.white24,
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Step Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary Bold Maneuver
                    Text(
                      step.primaryInstruction,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight:
                            isFocused ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),

                    // Secondary cues & landmarks (Signature Google Maps details)
                    if (step.secondaryInstruction != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2, right: 4),
                            child: Icon(
                              Icons.pin_drop,
                              size: 13,
                              color: AppTheme.sunsetCoral,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              step.secondaryInstruction!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 4),

                    // Badges & Distance Pill
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Distance pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.slateMuted.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'In ${step.distanceText} · ${step.durationText}',
                            style: const TextStyle(
                              color: AppTheme.accentCyan,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        // Toll indicator
                        if (step.isToll)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.sunsetCoral.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppTheme.sunsetCoral.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Text(
                              'Toll road',
                              style: TextStyle(
                                color: AppTheme.sunsetCoral,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                        // Road name tag
                        if (step.roadName != null &&
                            !step.primaryInstruction.contains(step.roadName!))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              step.roadName!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivalCard(String etaTime) {
    final dropoff = _dropoff;
    final address = dropoff?.address ?? 'Destination';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.sunsetCoral.withValues(alpha: 0.2),
            border: Border.all(color: AppTheme.sunsetCoral, width: 2),
          ),
          child: const Center(
            child: Icon(
              Icons.place,
              color: AppTheme.sunsetCoral,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Arrive at Destination',
                      style: TextStyle(
                        color: AppTheme.sunsetCoral,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      etaTime,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
