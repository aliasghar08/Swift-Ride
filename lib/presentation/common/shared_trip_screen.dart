import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/ride_status.dart';
import '../view_models/responsive_layout_helper.dart';
import '../view_models/shared_trip_view_model.dart';
import 'glass_container.dart';
import 'skeleton.dart';
import 'google_map_view.dart';
import 'map_markers.dart';
import 'staggered_animation.dart';

/// Public read-only view of a trip opened through a share link.
///
/// Every value is loaded from the `getSharedTrip` Cloud Function. It previously
/// rendered a fabricated trip — a hardcoded rider ("Alex Morgan") and driver
/// ("Marcus Vance • Toyota Camry Hybrid (7XYZ890)") drawn at coordinates derived
/// from the *viewer's* own GPS.
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
    _viewModel.load();
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
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: _buildAppBar(layout),
          body: _buildBody(layout),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(ResponsiveLayoutHelper layout) {
    final c = AppColors.of(layout.context);
    return AppBar(
      backgroundColor: Colors.white.withValues(alpha: 0.85),
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              boxShadow: AppTheme.glowShadow(
                AppTheme.primaryBlue,
                opacity: 0.2,
                blur: 8,
              ),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppTheme.accentCyan,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SwiftRide Live Trip Guardian',
              style: TextStyle(
                fontSize: layout.fontSize(15),
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (_viewModel.hasToken)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              icon: Icon(
                _viewModel.isCopied ? Icons.check : Icons.copy,
                size: 16,
                color: _viewModel.isCopied
                    ? AppTheme.emeraldGreen
                    : AppTheme.primaryBlue,
              ),
              label: Text(
                _viewModel.isCopied ? 'Copied' : 'Copy Link',
                style: TextStyle(
                  fontSize: layout.fontSize(12),
                  color: _viewModel.isCopied
                      ? AppTheme.emeraldGreen
                      : AppTheme.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: _viewModel.copyShareLink,
            ),
          ),
      ],
    );
  }

  Widget _buildBody(ResponsiveLayoutHelper layout) {
    if (_viewModel.isLoading) {
      // Skeleton mirrors the final layout (map + summary card) so the screen does
      // not jump when the trip arrives.
      return Stack(
        children: [
          Positioned.fill(
            child: SkeletonBox(
              height: double.infinity,
              borderRadius: BorderRadius.zero,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(layout.horizontalPadding),
                child: const SkeletonCard(lines: 2),
              ),
            ),
          ),
        ],
      );
    }

    final error = _viewModel.error;
    if (error != null) {
      return _buildMessage(
        layout,
        icon: Icons.link_off,
        title: 'Trip unavailable',
        message: error,
        onRetry: _viewModel.hasToken ? _viewModel.load : null,
      );
    }

    final info = _viewModel.info;
    if (info == null) {
      return _buildMessage(
        layout,
        icon: Icons.info_outline,
        title: 'Trip unavailable',
        message: 'We could not find any details for this trip.',
      );
    }

    final pickup = info.pickup;
    final dropoff = info.dropoff;
    final driverLat = info.driverLatitude;
    final driverLng = info.driverLongitude;

    // Centre on whatever real geometry we have. If there is none, say so rather
    // than inventing a location.
    final LatLng? centre = driverLat != null && driverLng != null
        ? LatLng(driverLat, driverLng)
        : (pickup != null
              ? LatLng(pickup.latitude, pickup.longitude)
              : (dropoff != null
                    ? LatLng(dropoff.latitude, dropoff.longitude)
                    : null));

    if (centre == null) {
      return _buildMessage(
        layout,
        icon: Icons.location_off,
        title: 'No location yet',
        message: 'This trip does not have any location data to display.',
      );
    }

    final markers = <Marker>{
      if (pickup != null)
        MapMarkers.pickup(
          LatLng(pickup.latitude, pickup.longitude),
          id: 'shared_pickup',
        ),
      if (dropoff != null)
        MapMarkers.dropoff(
          LatLng(dropoff.latitude, dropoff.longitude),
          id: 'shared_dropoff',
        ),
      if (driverLat != null && driverLng != null)
        MapMarkers.driver(
          driverId: 'shared',
          pos: LatLng(driverLat, driverLng),
          heading: info.driverHeading,
        ),
    };

    final routePoints = <LatLng>[
      if (driverLat != null && driverLng != null) LatLng(driverLat, driverLng),
      if (pickup != null) LatLng(pickup.latitude, pickup.longitude),
      if (dropoff != null) LatLng(dropoff.latitude, dropoff.longitude),
    ];

    return Stack(
      children: [
        GoogleMapView(
          initialCenter: centre,
          initialZoom: 15,
          mode: MapMode.liveTracking,
          darkMode: true,
          showTraffic: true,
          markers: markers,
          polylines: {
            if (routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('shared_route_casing'),
                points: routePoints,
                color: AppTheme.primaryNavy,
                width: 9,
              ),
            if (routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('shared_route'),
                points: routePoints,
                color: AppTheme.accentCyan,
                width: 5,
              ),
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: layout.horizontalPadding,
                  ),
                  child: StaggeredEntryWidget(
                    index: 0,
                    child: GlassContainer(
                      borderRadius: 24,
                      blur: 20,
                      padding: EdgeInsets.all(layout.scale(16)),
                      shadows: AppTheme.premiumElevation,
                      child: _buildTripSummary(layout, info),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTripSummary(ResponsiveLayoutHelper layout, SharedTripInfo info) {
    final c = AppColors.of(layout.context);
    final status = RideStatus.fromString(info.status);
    final eta = _viewModel.estimateRemainingMinutes();
    final vehicle = info.vehicleLabel;

    return Column(
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
                  Semantics(
                    liveRegion: true,
                    label: 'Trip status: ${status.displayName}',
                    child: Text(
                      'Trip ${status.displayName}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: layout.fontSize(13),
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    vehicle ?? 'Vehicle details unavailable',
                    style: TextStyle(
                      fontSize: layout.fontSize(11),
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (eta != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                  ),
                  boxShadow: AppTheme.glowShadow(
                    AppTheme.emeraldGreen,
                    opacity: 0.15,
                    blur: 6,
                  ),
                ),
                child: Text(
                  'ETA: $eta min',
                  style: TextStyle(
                    color: AppTheme.emeraldGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: layout.fontSize(12),
                  ),
                ),
              ),
          ],
        ),
        if (info.dropoff != null && info.dropoff!.address.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                size: 14,
                color: AppTheme.slateMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  info.dropoff!.address,
                  style: TextStyle(
                    fontSize: layout.fontSize(11),
                    color: AppTheme.slateMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMessage(
    ResponsiveLayoutHelper layout, {
    required IconData icon,
    required String title,
    required String message,
    Future<void> Function()? onRetry,
  }) {
    final c = AppColors.of(layout.context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
        child: Padding(
          padding: EdgeInsets.all(layout.horizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: AppTheme.slateMuted),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: layout.fontSize(15),
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: layout.fontSize(12),
                  color: AppTheme.slateMuted,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => onRetry(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
