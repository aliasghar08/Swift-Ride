import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/map_service.dart';
import '../common/google_map_view.dart';
import '../common/map_markers.dart';
import '../view_models/rider_view_model.dart';



class RoutePreviewScreen extends StatefulWidget {
  final RiderViewModel viewModel;

  const RoutePreviewScreen({
    super.key,
    required this.viewModel,
  });

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  GoogleMapController? _mapController;
  late int _selectedRouteIndex;

  @override
  void initState() {
    super.initState();
    MapMarkers.ensureOriginDot();
    _selectedRouteIndex = widget.viewModel.selectedRouteIndex;
  }

  void _selectRoute(int index) {
    if (index == _selectedRouteIndex) return;
    setState(() {
      _selectedRouteIndex = index;
      widget.viewModel.selectRoute(index);
    });
    final routes = widget.viewModel.routes;
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
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  static IconData _maneuverIcon(String maneuver) {
    switch (maneuver.toUpperCase()) {
      case 'TURN_LEFT':
      case 'TURN_SLIGHT_LEFT':
      case 'TURN_SHARP_LEFT':
        return Icons.turn_left;
      case 'TURN_RIGHT':
      case 'TURN_SLIGHT_RIGHT':
      case 'TURN_SHARP_RIGHT':
        return Icons.turn_right;
      case 'STRAIGHT':
        return Icons.straight;
      case 'ROUNDABOUT_LEFT':
      case 'ROUNDABOUT_RIGHT':
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
      case 'DEPART':
        return Icons.navigation;
      case 'DESTINATION':
        return Icons.place;
      default:
        return Icons.navigation;
    }
  }

  static String _formatStepDistance(double distanceKm) {
    if (distanceKm >= 1.0) {
      return '${distanceKm.toStringAsFixed(1)} km';
    } else {
      final meters = (distanceKm * 1000).round();
      return '$meters m';
    }
  }

  static Color _trafficColour(TrafficInterval? interval) {
    if (interval == null) return AppTheme.accentCyan;
    if (interval.isJam) return AppTheme.sunsetCoral;
    if (interval.isSlow) return AppTheme.amberWarning;
    return AppTheme.accentCyan;
  }

  Set<Polyline> _buildPolylines() {
    final routes = widget.viewModel.routes;
    if (routes.isEmpty) return const {};

    const casingWidth = 16;
    const fillWidth = 10;

    final set = <Polyline>{};

    // Unselected routes
    for (var i = 0; i < routes.length; i++) {
      if (i != _selectedRouteIndex) {
        set.add(
          Polyline(
            polylineId: PolylineId('preview_route_$i'),
            points: routes[i].polylinePoints,
            color: AppTheme.slateMuted.withValues(alpha: 0.45),
            width: 6,
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
          color: AppTheme.primaryNavy,
          width: casingWidth,
          zIndex: 0,
        ),
      );
      set.add(
        Polyline(
          polylineId: PolylineId('preview_route_${_selectedRouteIndex}_fill'),
          points: sel.polylinePoints,
          color: AppTheme.accentCyan,
          width: fillWidth,
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
            zIndex: 2,
          ),
        );
      }
    }

    for (final p in set) {
      debugPrint(
        '[POLY-DEBUG] id=${p.polylineId.value} width=${p.width} points=${p.points.length}',
      );
    }

    return set;
  }

  Set<Marker> _buildMarkers() {
    final pickup = widget.viewModel.pickupLocation;
    final dropoff = widget.viewModel.dropoffLocation;
    return {
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
  }

  @override
  Widget build(BuildContext context) {
    final routes = widget.viewModel.routes;
    final hasRoute = routes.isNotEmpty && _selectedRouteIndex < routes.length;
    final selected = hasRoute ? routes[_selectedRouteIndex] : null;

    final initialCenter = widget.viewModel.pickupLocation != null
        ? LatLng(
            widget.viewModel.pickupLocation!.latitude,
            widget.viewModel.pickupLocation!.longitude,
          )
        : const LatLng(31.5580, 74.3507);

    return Scaffold(
      backgroundColor: AppTheme.primaryNavy,
      body: Stack(
        children: [
          // 1. Full-screen map
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

          // 2. Top-left Close Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: Material(
              color: AppTheme.primaryNavy.withValues(alpha: 0.85),
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),

          // 3. Draggable Directions Bottom Sheet
          DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.25,
            maxChildSize: 0.90,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 16,
                      offset: Offset(0, -4),
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
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Directions',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),

                    if (selected != null) ...[
                      // Summary Row
                      Text(
                        '${selected.distanceKm.toStringAsFixed(1)} km · ${selected.durationMin.toStringAsFixed(0)} min',
                        style: const TextStyle(
                          color: AppTheme.accentCyan,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Driver earns PKR ${selected.economics.driverProfit.round()} (${selected.economics.profitPerMin.toStringAsFixed(1)} PKR/min)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),

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
                                          return 'Best for Driver';
                                        default:
                                          return l;
                                      }
                                    }).join(' · ')
                                  : 'Option ${idx + 1}';

                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(label),
                                  selected: isSelected,
                                  onSelected: (_) => _selectRoute(idx),
                                  selectedColor: AppTheme.primaryBlue,
                                  backgroundColor: AppTheme.slateMuted.withValues(alpha: 0.2),
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],

                    const Divider(color: Colors.white12, height: 24),

                    // Turn List
                    const Text(
                      'Turn-by-turn guidance',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (selected == null || selected.steps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No directions available for this route.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    else
                      ...selected.steps.map((step) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.slateMuted.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _maneuverIcon(step.maneuver),
                                  color: AppTheme.accentCyan,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.instruction,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'In ${_formatStepDistance(step.distanceKm)}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 20),

                    // Start Ride Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Start Ride',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
