import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../view_models/responsive_layout_helper.dart';
import '../view_models/shared_trip_view_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'glass_container.dart';
import 'google_map_view.dart';
import 'map_markers.dart';
import 'staggered_animation.dart';

class SharedTripScreen extends StatefulWidget {
  final String? token;

  const SharedTripScreen({super.key, this.token});

  @override
  State<SharedTripScreen> createState() => _SharedTripScreenState();
}

class _SharedTripScreenState extends State<SharedTripScreen> {
  late final SharedTripViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SharedTripViewModel(token: widget.token);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return CustomConsumer<RideProvider>(
          builder: (context, rideProv, _) {
            return CustomConsumer<LocationProvider>(
              builder: (context, locProv, _) {
                final ride = rideProv.currentRide;
                final eta = _viewModel.estimateRemainingMinutes(ride);

                return Scaffold(
                  extendBodyBehindAppBar: true,
                  appBar: AppBar(
                    backgroundColor: Colors.white.withValues(alpha: 0.85),
                    elevation: 0,
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            boxShadow: AppTheme.glowShadow(AppTheme.primaryBlue, opacity: 0.2, blur: 8),
                          ),
                          child: const Icon(Icons.shield_outlined, color: AppTheme.accentCyan, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'SwiftRide Live Trip Guardian',
                            style: TextStyle(fontSize: layout.fontSize(15), fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TextButton.icon(
                          icon: Icon(
                            _viewModel.isCopied ? Icons.check : Icons.copy,
                            size: 16,
                            color: _viewModel.isCopied ? AppTheme.emeraldGreen : AppTheme.primaryBlue,
                          ),
                          label: Text(
                            _viewModel.isCopied ? 'Copied' : 'Copy Link',
                            style: TextStyle(
                              fontSize: layout.fontSize(12),
                              color: _viewModel.isCopied ? AppTheme.emeraldGreen : AppTheme.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () {
                            _viewModel.copyShareLink('https://swiftride.app/track?token=${widget.token ?? 'demo'}');
                          },
                        ),
                      ),
                    ],
                  ),
                  body: Stack(
                    children: [
                      GoogleMapView(
                        initialCenter: LatLng(locProv.latitude, locProv.longitude),
                        initialZoom: 15,
                        mode: MapMode.liveTracking,
                        darkMode: true,
                        showTraffic: true,
                        markers: {
                          MapMarkers.driver(
                            driverId: 'driver',
                            pos: LatLng(locProv.latitude, locProv.longitude),
                            heading: locProv.heading,
                          ),
                          MapMarkers.pickup(LatLng(locProv.latitude + 0.005, locProv.longitude - 0.004)),
                          MapMarkers.dropoff(LatLng(locProv.latitude - 0.012, locProv.longitude + 0.015)),
                        },
                        polylines: {
                          Polyline(
                            polylineId: const PolylineId('shared_route'),
                            points: [
                              LatLng(locProv.latitude + 0.005, locProv.longitude - 0.004),
                              LatLng(locProv.latitude, locProv.longitude),
                              LatLng(locProv.latitude - 0.012, locProv.longitude + 0.015),
                            ],
                            color: Colors.cyanAccent,
                            width: 5,
                          ),
                        },
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
                              child: StaggeredEntryWidget(
                                index: 0,
                                child: GlassContainer(
                                  borderRadius: 24,
                                  blur: 20,
                                  padding: EdgeInsets.all(layout.scale(16)),
                                  shadows: AppTheme.premiumElevation,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          PulsingGlowWidget(
                                            glowColor: AppTheme.emeraldGreen,
                                            child: const CircleAvatar(
                                              backgroundColor: AppTheme.emeraldGreen,
                                              child: Icon(Icons.check, color: Colors.white),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ride != null
                                                      ? 'Alex Morgan is on trip • ${ride.status.displayName}'
                                                      : 'Active Ride Tracking Stream',
                                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: layout.fontSize(13), color: const Color(0xFF0F172A)),
                                                ),
                                                Text(
                                                  'Marcus Vance • Toyota Camry Hybrid (7XYZ890)',
                                                  style: TextStyle(fontSize: layout.fontSize(11), color: AppTheme.slateMuted),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.3)),
                                              boxShadow: AppTheme.glowShadow(AppTheme.emeraldGreen, opacity: 0.15, blur: 6),
                                            ),
                                            child: Text(
                                              'ETA: $eta min',
                                              style: TextStyle(color: AppTheme.emeraldGreen, fontWeight: FontWeight.w800, fontSize: layout.fontSize(12)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
