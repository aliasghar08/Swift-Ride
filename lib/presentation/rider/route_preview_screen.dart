import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/route_option.dart';
import '../common/google_map_view.dart';
import '../common/map_markers.dart';
import '../view_models/rider_view_model.dart';

class TurnInstruction {
  final IconData icon;
  final String instruction;
  final String distanceText;

  const TurnInstruction({
    required this.icon,
    required this.instruction,
    required this.distanceText,
  });
}

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
  late List<TurnInstruction> _turns;

  @override
  void initState() {
    super.initState();
    _selectedRouteIndex = widget.viewModel.selectedRouteIndex;
    _updateTurns();
  }

  void _updateTurns() {
    final routes = widget.viewModel.routes;
    if (routes.isNotEmpty && _selectedRouteIndex < routes.length) {
      _turns = _buildTurns(routes[_selectedRouteIndex].polylinePoints);
    } else {
      _turns = [];
    }
  }

  void _selectRoute(int index) {
    if (index == _selectedRouteIndex) return;
    setState(() {
      _selectedRouteIndex = index;
      widget.viewModel.selectRoute(index);
      _updateTurns();
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

  static double _calculateBearing(LatLng start, LatLng end) {
    final startLat = start.latitude * (pi / 180.0);
    final startLng = start.longitude * (pi / 180.0);
    final endLat = end.latitude * (pi / 180.0);
    final endLng = end.longitude * (pi / 180.0);

    final dLng = endLng - startLng;
    final y = sin(dLng) * cos(endLat);
    final x = cos(startLat) * sin(endLat) - sin(startLat) * cos(dLng);
    final bearing = atan2(y, x) * (180.0 / pi);
    return (bearing + 360.0) % 360.0;
  }

  static double _calculateDistanceMeters(LatLng p1, LatLng p2) {
    const earthRadius = 6371000.0;
    final dLat = (p2.latitude - p1.latitude) * (pi / 180.0);
    final dLng = (p2.longitude - p1.longitude) * (pi / 180.0);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(p1.latitude * (pi / 180.0)) *
            cos(p2.latitude * (pi / 180.0)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static List<TurnInstruction> _buildTurns(List<LatLng> points) {
    if (points.length < 3) {
      return [
        const TurnInstruction(
          icon: Icons.straight,
          instruction: 'Head straight to destination',
          distanceText: '',
        ),
      ];
    }

    final turns = <TurnInstruction>[];
    double accumulatedMeters = 0.0;

    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      accumulatedMeters += _calculateDistanceMeters(curr, next);

      final b1 = _calculateBearing(prev, curr);
      final b2 = _calculateBearing(curr, next);
      final delta = (b2 - b1 + 540.0) % 360.0 - 180.0;

      if (delta.abs() > 30.0) {
        final isLeft = delta < 0;
        final distStr = accumulatedMeters >= 1000
            ? '${(accumulatedMeters / 1000).toStringAsFixed(1)} km'
            : '${accumulatedMeters.round()} m';

        turns.add(TurnInstruction(
          icon: isLeft ? Icons.turn_left : Icons.turn_right,
          instruction: isLeft ? 'Turn left' : 'Turn right',
          distanceText: distStr,
        ));
        accumulatedMeters = 0;
      }
    }

    if (turns.isEmpty) {
      final totalKm = accumulatedMeters / 1000;
      turns.add(TurnInstruction(
        icon: Icons.straight,
        instruction: 'Continue along main route',
        distanceText: '${totalKm.toStringAsFixed(1)} km',
      ));
    }

    turns.add(const TurnInstruction(
      icon: Icons.place,
      instruction: 'Arrive at destination',
      distanceText: '',
    ));

    return turns;
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

    final casingWidth = kIsWeb ? 18 : 16;
    final fillWidth = kIsWeb ? 12 : 10;

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

      for (var j = 0; j < sel.trafficIntervals.length; j++) {
        final interval = sel.trafficIntervals[j];
        final seg = TrafficInterval.segment(
          sel.polylinePoints,
          sel.trafficIntervals,
        );
        for (var k = 0; k < seg.length; k++) {
          set.add(
            Polyline(
              polylineId: PolylineId(
                'preview_route_${_selectedRouteIndex}_traffic_$k',
              ),
              points: seg[k].points,
              color: _trafficColour(seg[k].interval),
              width: fillWidth,
              zIndex: 2,
            ),
          );
        }
      }
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
            initialChildSize: 0.40,
            minChildSize: 0.20,
            maxChildSize: 0.85,
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
                              final label = r.badges.isNotEmpty
                                  ? r.badges.first.displayName
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

                    if (_turns.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No turns detected.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    else
                      ..._turns.map((turn) {
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
                                  turn.icon,
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
                                      turn.instruction,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (turn.distanceText.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'In ${turn.distanceText}',
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
