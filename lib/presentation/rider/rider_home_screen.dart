import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/models/location_point_model.dart';
import '../../domain/models/payment_rail.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_offer_model.dart';
import '../../domain/models/ride_status.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/safety_provider.dart';
import '../../services/firestore/firestore_driver_service.dart';
import '../../services/firestore/firestore_user_service.dart';
import '../../services/map_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../common/confirm_action.dart';
import '../common/glass_container.dart';
import '../common/google_map_view.dart';
import '../common/map_markers.dart';
import '../common/staggered_animation.dart';
import '../view_models/responsive_layout_helper.dart';
import '../view_models/rider_view_model.dart';
import 'address_search_screen.dart';
import '../../ai/ai.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  String? _driverPhone;
  String? _driverName;
  String? _driverVehicle;
  String? _driverPhoneForDriverId;

  late final RiderViewModel _viewModel;
  GoogleMapController? _mapController;

  bool _viewModelInitialized = false;
  bool _waitingForGps = true;
  
  // UI Minimization States
  bool _isTopCardMinimized = false;
  bool _isBottomSheetMinimized = false;

  @override
  void initState() {
    super.initState();
    _viewModel = RiderViewModel();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locProv =
          CustomChangeNotifierProvider.of<LocationProvider>(context);

      final fix = await locProv.waitForFirstFix(
        timeout: const Duration(seconds: 12),
      );
      if (!mounted) return;

      if (fix != null) {
        _viewModel.initializeFromCoordinates(fix.latitude, fix.longitude);
        setState(() => _waitingForGps = false);
      } else {
        setState(() => _waitingForGps = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'We could not read your GPS. Tap the pin icon to place your '
              'pickup manually, or enable location in Settings.',
            ),
            duration: const Duration(seconds: 6),
            backgroundColor: AppTheme.amberWarning,
          ),
        );
      }
      _viewModelInitialized = true;
    });
  }

  void _ensureDriverPhone(String? driverId) {
    if (driverId == null || driverId == _driverPhoneForDriverId) return;
    _driverPhoneForDriverId = driverId;
    _driverPhone = null;

    FirestoreUserService().getUser(driverId).then((user) {
      if (!mounted || _driverPhoneForDriverId != driverId) return;
      setState(() {
        _driverPhone = user?.phone;
        _driverName = user?.fullName;
      });
    }).catchError((Object e) {
      debugPrint('[RiderHome] driver lookup failed: $e');
    });

    FirestoreDriverService().getDriverProfile(driverId).then((profile) {
      if (!mounted || _driverPhoneForDriverId != driverId || profile == null) {
        return;
      }
      final v = profile.vehicle;
      final summary =
          [v.color, v.make, v.model].where((p) => p.trim().isNotEmpty).join(' ');
      final plate = v.plate.isEmpty ? '' : ' (${v.plate})';
      final rating =
          profile.rating > 0 ? ' • ★ ${profile.rating.toStringAsFixed(2)}' : '';
      setState(() {
        _driverVehicle = summary.isEmpty ? null : '$summary$plate$rating';
      });
    }).catchError((Object e) {
      debugPrint('[RiderHome] driver profile lookup failed: $e');
    });
  }

  Future<void> _openAddressSearch({required bool isPickup}) async {
    final result = await Navigator.of(context).push<LocationPoint>(
      MaterialPageRoute(
        builder: (_) => AddressSearchScreen(
          title: isPickup ? 'Set Pickup Location' : 'Set Destination',
          initialQuery: isPickup
              ? _viewModel.pickupController.text
              : _viewModel.dropoffController.text,
        ),
      ),
    );
    if (result != null) {
      if (isPickup) {
        _viewModel.setPickup(result);
      } else {
        _viewModel.setDropoff(result);
        setState(() => _isBottomSheetMinimized = false); // Auto-expand fare on new search
      }
    }
  }

  @override
  void dispose() {
    _mapController = null;
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    final locProv = CustomChangeNotifierProvider.of<LocationProvider>(context);
    final authProv = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    final safetyProv = CustomChangeNotifierProvider.of<SafetyProvider>(context);

    return ListenableBuilder(
      listenable: Listenable.merge([_viewModel, locProv]),
      builder: (context, _) {
        final currentRide = rideProv.currentRide;
        _ensureDriverPhone(currentRide?.driverId);
        final driverTelemetry = currentRide?.driverLocation;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctrl = _mapController;
          if (ctrl == null || currentRide != null) return;
          ctrl.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(locProv.latitude, locProv.longitude),
            ),
          );
        });

        return Scaffold(
          body: Stack(
            children: [
              GoogleMapView(
                initialCenter: LatLng(locProv.latitude, locProv.longitude),
                initialZoom: 15,
                semanticsLabel: _viewModel.isPinMode
                    ? 'Map with a pin at the centre. Drag to choose a location.'
                    : (currentRide != null
                        ? 'Live map of your trip. Status: ${currentRide.status.displayName}.'
                        : 'Map of your area. Choose a pickup and destination to see a route.'),
                mode: _viewModel.isPinMode
                    ? MapMode.pinPicker
                    : (currentRide != null
                        ? MapMode.liveTracking
                        : MapMode.viewOnly),
                darkMode: true,
                showTraffic: true,
                onControllerCreated: (controller) {
                  _mapController = controller;
                },
                onPinChanged: (coords) => _viewModel.updatePinnedCoordinates(
                  coords.latitude,
                  coords.longitude,
                ),
                markers: {
                  if (currentRide == null && _viewModel.pickupLocation != null)
                    MapMarkers.pickup(
                      LatLng(
                        _viewModel.pickupLocation!.latitude,
                        _viewModel.pickupLocation!.longitude,
                      ),
                      id: 'search_pickup',
                    ),
                  if (currentRide == null && _viewModel.dropoffLocation != null)
                    MapMarkers.dropoff(
                      LatLng(
                        _viewModel.dropoffLocation!.latitude,
                        _viewModel.dropoffLocation!.longitude,
                      ),
                      id: 'search_dropoff',
                    ),
                  if (currentRide != null) ...[
                    MapMarkers.pickup(
                      LatLng(
                        currentRide.pickup.latitude,
                        currentRide.pickup.longitude,
                      ),
                      id: 'ride_pickup',
                    ),
                    MapMarkers.dropoff(
                      LatLng(
                        currentRide.dropoff.latitude,
                        currentRide.dropoff.longitude,
                      ),
                      id: 'ride_dropoff',
                    ),
                    if (driverTelemetry != null && !driverTelemetry.isStale)
                      MapMarkers.driver(
                        driverId: currentRide.driverId ?? 'driver',
                        pos: LatLng(
                          driverTelemetry.latitude,
                          driverTelemetry.longitude,
                        ),
                        heading: driverTelemetry.heading,
                      ),
                  ],
                },
                polylines: {
                  if (_viewModel.routePolyline.isNotEmpty) ...[
                    Polyline(
                      polylineId: const PolylineId('rider_preview_route_casing'),
                      points: _viewModel.routePolyline,
                      color: AppTheme.primaryNavy,
                      width: 9,
                    ),
                    ...TrafficInterval.segment(
                      _viewModel.routePolyline,
                      _viewModel.routeTraffic,
                    ).asMap().entries.map((entry) {
                      final interval = entry.value.interval;
                      return Polyline(
                        polylineId:
                            PolylineId('rider_preview_traffic_${entry.key}'),
                        points: entry.value.points,
                        color: _trafficColour(interval),
                        width: 5,
                      );
                    }),
                  ] else if (currentRide != null) ...[
                    Polyline(
                      polylineId: const PolylineId('rider_active_route_casing'),
                      points: [
                        if (driverTelemetry != null && !driverTelemetry.isStale)
                          LatLng(driverTelemetry.latitude,
                              driverTelemetry.longitude)
                        else
                          LatLng(currentRide.pickup.latitude,
                              currentRide.pickup.longitude),
                        LatLng(
                            currentRide.pickup.latitude, currentRide.pickup.longitude),
                        LatLng(currentRide.dropoff.latitude,
                            currentRide.dropoff.longitude),
                      ],
                      color: AppTheme.primaryNavy,
                      width: 9,
                    ),
                    Polyline(
                      polylineId: const PolylineId('rider_active_route'),
                      points: [
                        if (driverTelemetry != null && !driverTelemetry.isStale)
                          LatLng(driverTelemetry.latitude,
                              driverTelemetry.longitude)
                        else
                          LatLng(currentRide.pickup.latitude,
                              currentRide.pickup.longitude),
                        LatLng(
                            currentRide.pickup.latitude, currentRide.pickup.longitude),
                        LatLng(currentRide.dropoff.latitude,
                            currentRide.dropoff.longitude),
                      ],
                      color: AppTheme.accentCyan,
                      width: 5,
                    ),
                  ],
                },
              ),

              if (_waitingForGps && currentRide == null)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: layout.maxCardWidth),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: layout.horizontalPadding,
                          vertical: layout.scale(8),
                        ),
                        child: GlassContainer(
                          borderRadius: 16,
                          blur: 14,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.accentCyan),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Finding your location…',
                                  style: TextStyle(
                                    color: AppColors.of(context).textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (currentRide == null && !_waitingForGps)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: layout.maxCardWidth),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: layout.horizontalPadding,
                          vertical: layout.scale(8),
                        ),
                        child: _buildAddressCard(layout),
                      ),
                    ),
                  ),
                ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                    child: currentRide == null
                        ? _buildFareProposalSheet(
                            layout, rideProv, authProv, driverProv)
                        : _buildActiveRideSheet(
                            layout: layout,
                            ride: currentRide,
                            offers: rideProv.activeOffers,
                            rideProv: rideProv,
                            safetyProv: safetyProv,
                            authProv: authProv,
                            locProv: locProv,
                          ),
                  ),
                ),
              ),

              CustomConsumer<SafetyCheckProvider>(
                builder: (context, safetyCheck, _) {
                  if (!safetyCheck.isSafetyActive ||
                      safetyCheck.message == null) {
                    return const SizedBox.shrink();
                  }
                  return SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: layout.maxCardWidth),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.horizontalPadding,
                            vertical: layout.scale(8),
                          ),
                          child: SafetyCheckOverlay(
                            rideId: safetyCheck.rideId ??
                                (currentRide?.id ?? 'active_ride'),
                            flagType: safetyCheck.flagType ?? 'SAFETY_CHECK',
                            message: safetyCheck.message!,
                            onDismiss: () => safetyCheck.dismissCheck(),
                            onNeedHelp: () async {
                              safetyCheck.triggerEmergencySos();

                              final ride = currentRide;
                              final result = await _viewModel.dispatchSos(
                                safetyProv: safetyProv,
                                rideId: ride?.id ?? '',
                                userId: authProv.currentUser.id,
                                latitude: locProv.latitude,
                                longitude: locProv.longitude,
                              );

                              if (!context.mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result.reachedAnyone
                                        ? 'Emergency alert sent. ${result.message}'
                                        : 'Alert raised on this device, but we could not '
                                            'reach anyone. Call emergency services directly.',
                                  ),
                                  backgroundColor: result.reachedAnyone
                                      ? AppTheme.emeraldGreen
                                      : AppTheme.sunsetCoral,
                                  duration: const Duration(seconds: 6),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'my_location_btn',
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: AppTheme.accentCyan,
                child: const Icon(Icons.my_location, size: 20),
                onPressed: () {
                  final loc = CustomChangeNotifierProvider.read<LocationProvider>(context);
                  if (loc.hasRealFix && _mapController != null) {
                    _mapController!.animateCamera(
                      CameraUpdate.newLatLng(LatLng(loc.latitude, loc.longitude)),
                    );
                  } else if (!loc.hasRealFix) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Waiting for GPS signal...'),
                        backgroundColor: AppTheme.amberWarning,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              PulsingGlowWidget(
                glowColor: AppTheme.accentCyan,
                minSpread: 1.0,
                maxSpread: 5.0,
                child: FloatingActionButton.extended(
                  heroTag: 'ai_chat_btn',
                  onPressed: () => Navigator.of(context).pushNamed('/ai-chat'),
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.accentCyan,
                  icon: const Icon(Icons.auto_awesome, size: 20),
                  label: const Text('Ask AI',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Color _trafficColour(TrafficInterval? interval) {
    if (interval == null) return AppTheme.accentCyan;
    if (interval.isJam) return AppTheme.sunsetCoral;
    if (interval.isSlow) return AppTheme.amberWarning;
    return AppTheme.accentCyan;
  }

  Widget _buildAddressCard(ResponsiveLayoutHelper layout) {
    if (_isTopCardMinimized) {
      return GestureDetector(
        onTap: () => setState(() => _isTopCardMinimized = false),
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 100) {
            setState(() => _isTopCardMinimized = false);
          }
        },
        child: GlassContainer(
          borderRadius: 20,
          blur: 18,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search, color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                'Tap to expand search', 
                style: TextStyle(color: AppColors.of(context).textPrimary, fontWeight: FontWeight.w600)
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
          setState(() => _isTopCardMinimized = true);
        }
      },
      child: StaggeredEntryWidget(
        index: 0,
        duration: const Duration(milliseconds: 400),
        child: GlassContainer(
          borderRadius: 20,
          blur: 18,
          padding: EdgeInsets.all(layout.scale(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.radio_button_checked,
                      color: AppTheme.emeraldGreen, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openAddressSearch(isPickup: true),
                      child: IgnorePointer(
                        child: TextField(
                          controller: _viewModel.pickupController,
                          style: TextStyle(fontSize: layout.fontSize(14)),
                          decoration: const InputDecoration(
                            hintText: 'Pickup Location',
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _viewModel.isPinMode ? Icons.check_circle : Icons.pin_drop,
                      color: _viewModel.isPinMode
                          ? AppTheme.emeraldGreen
                          : AppTheme.primaryBlue,
                    ),
                    tooltip: 'Set Pickup Pin on Map',
                    onPressed: () => _viewModel.togglePinMode(),
                  ),
                ],
              ),
              const Divider(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on,
                      color: AppTheme.sunsetCoral, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openAddressSearch(isPickup: false),
                      child: IgnorePointer(
                        child: TextField(
                          controller: _viewModel.dropoffController,
                          style: TextStyle(fontSize: layout.fontSize(14)),
                          decoration: const InputDecoration(
                            hintText: 'Where to? (Destination)',
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFareProposalSheet(
    ResponsiveLayoutHelper layout,
    RideProvider rideProv,
    AuthProvider authProv,
    DriverProvider driverProv,
  ) {
    if (_isBottomSheetMinimized) {
      return GestureDetector(
        onTap: () => setState(() => _isBottomSheetMinimized = false),
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
            setState(() => _isBottomSheetMinimized = false);
          }
        },
        child: GlassContainer(
          borderRadius: 28,
          blur: 24,
          padding: EdgeInsets.fromLTRB(
            layout.horizontalPadding, 12, layout.horizontalPadding,
            layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))
              ),
              const SizedBox(height: 12),
              Text('Tap to expand fare options', style: TextStyle(color: AppColors.of(context).textPrimary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    final c = AppColors.of(layout.context);
    final suggested = _viewModel.suggestedFare;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 100) {
          setState(() => _isBottomSheetMinimized = true);
        }
      },
      child: GlassContainer(
        borderRadius: 28,
        blur: 24,
        padding: EdgeInsets.fromLTRB(
          layout.horizontalPadding,
          14,
          layout.horizontalPadding,
          layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            SizedBox(height: layout.scale(12)),
            StaggeredEntryWidget(
              index: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _viewModel.routeIsEstimated &&
                              _viewModel.estimatedDistanceKm > 0
                          ? 'Approx ${_viewModel.estimatedDistanceKm}km • ${_viewModel.estimatedDurationMin.toInt()} min (direct estimate)'
                          : '${_viewModel.estimatedDistanceKm}km • ${_viewModel.estimatedDurationMin.toInt()} min',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateMuted,
                          fontSize: layout.fontSize(12)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Suggested: ${CurrencyFormatter.format(suggested)}',
                      style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(12)),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: layout.scale(10)),
            StaggeredEntryWidget(
              index: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your Offer (Rider sets the price):',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(14))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        height: layout.touchTarget(48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('PKR',
                            style: TextStyle(
                                fontSize: layout.fontSize(14),
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: layout.touchTarget(48),
                          child: TextField(
                            controller: _viewModel.fareController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) =>
                                _viewModel.markFareEditedByUser(),
                            style: TextStyle(
                                fontSize: layout.fontSize(18),
                                fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              hintText: 'Enter fare in PKR',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        height: layout.touchTarget(48),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () => _viewModel.quickIncrementFare(50.0),
                          child: const Text('+50'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: layout.touchTarget(48),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () => _viewModel.quickIncrementFare(100.0),
                          child: const Text('+100'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: layout.scale(10)),
            StaggeredEntryWidget(
              index: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.credit_card,
                        size: 16, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Payment: ${_viewModel.selectedPaymentMethod}',
                        style: TextStyle(
                            fontSize: layout.fontSize(12),
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showPaymentMethodSheet(context),
                      child: Text(
                        'Change',
                        style: TextStyle(
                            fontSize: layout.fontSize(12),
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: layout.scale(12)),
            StaggeredEntryWidget(
              index: 3,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.glowShadow(AppTheme.primaryBlue,
                      opacity: 0.35, blur: 16),
                ),
                height: layout.touchTarget(50),
                child: ElevatedButton(
                  onPressed: rideProv.isSubmitting
                      ? null
                      : () async {
                          final ok = await _viewModel.submitRideRequest(
                              rideProv: rideProv);
                          if (!mounted || ok) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                rideProv.lastError ??
                                    'Choose a pickup and destination before requesting a ride.',
                              ),
                              backgroundColor: AppTheme.sunsetCoral,
                            ),
                          );
                        },
                  child: rideProv.isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Find Nearby Drivers (0% Commission)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRideSheet({
    required ResponsiveLayoutHelper layout,
    required RideModel ride,
    required List<RideOffer> offers,
    required RideProvider rideProv,
    required SafetyProvider safetyProv,
    required AuthProvider authProv,
    required LocationProvider locProv,
  }) {
    if (_isBottomSheetMinimized) {
      return GestureDetector(
        onTap: () => setState(() => _isBottomSheetMinimized = false),
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
            setState(() => _isBottomSheetMinimized = false);
          }
        },
        child: GlassContainer(
          borderRadius: 28,
          blur: 24,
          padding: EdgeInsets.fromLTRB(
            layout.horizontalPadding, 12, layout.horizontalPadding,
            layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))
              ),
              const SizedBox(height: 12),
              Text('Tap to expand trip details', style: TextStyle(color: AppColors.of(context).textPrimary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 100) {
          setState(() => _isBottomSheetMinimized = true);
        }
      },
      child: GlassContainer(
        borderRadius: 28,
        blur: 24,
        padding: EdgeInsets.fromLTRB(
          layout.horizontalPadding,
          14,
          layout.horizontalPadding,
          layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            SizedBox(height: layout.scale(10)),
            StaggeredEntryWidget(
              index: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sync,
                            color: AppTheme.primaryBlue, size: 16),
                        const SizedBox(width: 6),
                        Semantics(
                          liveRegion: true,
                          label: 'Trip status: ${ride.status.displayName}',
                          child: Text(
                            ride.status.displayName,
                            style: TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: layout.fontSize(13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.darkNavy,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: AppTheme.glowShadow(AppTheme.accentCyan,
                          opacity: 0.25, blur: 8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined,
                            color: AppTheme.accentCyan, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'PIN: ${ride.pin}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            fontSize: layout.fontSize(13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (ride.status == RideStatus.requested) ...[
              SizedBox(height: layout.scale(12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Incoming Driver Offers:',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(14))),
                  Text('${offers.length} drivers nearby',
                      style: TextStyle(
                          color: AppTheme.slateMuted,
                          fontSize: layout.fontSize(12))),
                ],
              ),
              const SizedBox(height: 8),
              ...offers.asMap().entries.map(
                    (entry) =>
                        _buildOfferCard(layout, entry.value, rideProv, entry.key),
                  ),
              const SizedBox(height: 8),
            ],
            if (ride.status != RideStatus.requested) ...[
              SizedBox(height: layout.scale(12)),
              StaggeredEntryWidget(
                index: 1,
                child: GlassContainer(
                  borderRadius: 14,
                  blur: 10,
                  padding: const EdgeInsets.all(12),
                  backgroundColor: Colors.white.withValues(alpha: 0.8),
                  borderColor: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            AppTheme.primaryBlue.withValues(alpha: 0.1),
                        child: const Icon(Icons.person,
                            color: AppTheme.primaryBlue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _driverName?.isNotEmpty == true
                                  ? _driverName!
                                  : (ride.driverId == null
                                      ? 'Finding your driver…'
                                      : 'Driver assigned'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: layout.fontSize(13)),
                            ),
                            Text(
                              _driverVehicle ??
                                  (ride.driverId == null
                                      ? 'Waiting for a driver to accept'
                                      : 'Loading vehicle details…'),
                              style: TextStyle(
                                  fontSize: layout.fontSize(11),
                                  color: AppTheme.slateMuted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(
                            ride.acceptedFare ?? ride.offeredFare),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: layout.fontSize(15),
                            color: AppTheme.emeraldGreen),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SizedBox(height: layout.scale(14)),
            if (rideProv.activeSos != null) ...[
              Container(
                padding: EdgeInsets.all(layout.scale(12)),
                decoration: BoxDecoration(
                  color: AppTheme.sunsetCoral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.sunsetCoral.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emergency,
                        color: AppTheme.sunsetCoral, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Emergency alert active. Your driver and trusted contacts '
                        'have been notified.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.of(context).textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _standDownSos(rideProv),
                      child: const Text("I'm safe"),
                    ),
                  ],
                ),
              ),
              SizedBox(height: layout.scale(10)),
            ],
            StaggeredEntryWidget(
              index: 2,
              child: Row(
                children: [
                  SizedBox(
                    height: layout.touchTarget(48),
                    width: layout.touchTarget(48),
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        foregroundColor: AppTheme.emeraldGreen,
                      ),
                      icon: const Icon(Icons.phone),
                      tooltip: _driverPhone == null
                          ? 'Driver phone unavailable'
                          : 'Call Driver',
                      onPressed: _driverPhone == null
                          ? null
                          : () => _viewModel.callDriver(_driverPhone!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: layout.touchTarget(48),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text('Share Trip'),
                        onPressed: () async {
                          final url = await _viewModel.generateShareLink(
                            safetyProv: safetyProv,
                            rideProv: rideProv,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                url != null
                                    ? 'Trip share link ready: $url'
                                    : 'We could not create a share link. Check your connection and try again.',
                              ),
                              backgroundColor: url != null
                                  ? AppTheme.primaryBlue
                                  : AppTheme.sunsetCoral,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PulsingGlowWidget(
                    glowColor: AppTheme.sunsetCoral,
                    minSpread: 1.0,
                    maxSpread: 5.0,
                    child: SizedBox(
                      height: layout.touchTarget(48),
                      width: layout.touchTarget(48),
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor:
                              AppTheme.sunsetCoral.withValues(alpha: 0.18),
                          foregroundColor: AppTheme.sunsetCoral,
                        ),
                        icon: const Icon(Icons.warning_amber_rounded),
                        tooltip: 'Emergency SOS',
                        onPressed: () => _showSosDialog(
                          context,
                          safetyProv,
                          ride.id,
                          authProv.currentUser.id,
                          locProv.latitude,
                          locProv.longitude,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: layout.touchTarget(48),
                    width: layout.touchTarget(48),
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                      ),
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel Ride',
                      onPressed: () async {
                        final confirmed = await confirmAction(
                          context,
                          title: 'Cancel this ride?',
                          message:
                              'Your driver may already be on the way. Cancelling after a driver has accepted can incur a cancellation fee.',
                          confirmLabel: 'Cancel ride',
                          cancelLabel: 'Keep ride',
                          destructive: true,
                          icon: Icons.warning_amber_rounded,
                        );
                        if (!confirmed) return;
                        rideProv.cancelRide('User cancelled');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferCard(ResponsiveLayoutHelper layout, RideOffer offer,
      RideProvider rideProv, int index) {
    return StaggeredEntryWidget(
      index: index,
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 8),
        borderRadius: 14,
        blur: 12,
        padding: const EdgeInsets.all(12),
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        borderColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
        shadows: AppTheme.glowShadow(AppTheme.primaryBlue,
            opacity: 0.08, blur: 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
              child: const Icon(Icons.drive_eta, color: AppTheme.primaryBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(offer.driverName,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: layout.fontSize(13))),
                      const SizedBox(width: 6),
                      Text('★ ${offer.driverRating}',
                          style: TextStyle(
                              fontSize: layout.fontSize(11),
                              color: Colors.orange)),
                    ],
                  ),
                  Text(
                    '${offer.vehicleSummary} • ${offer.etaMinutes} min away',
                    style: TextStyle(
                        fontSize: layout.fontSize(11),
                        color: AppTheme.slateMuted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(offer.counterFare),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: layout.fontSize(15),
                      color: AppTheme.primaryBlue),
                ),
                const SizedBox(height: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    backgroundColor: AppTheme.emeraldGreen,
                  ),
                  onPressed: rideProv.isAcceptingOffer
                      ? null
                      : () => _viewModel.acceptDriverOffer(rideProv, offer.id),
                  child: rideProv.isAcceptingOffer
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentMethodSheet(BuildContext context) {
    final c = AppColors.of(context);
    final ride = CustomChangeNotifierProvider.of<RideProvider>(context).currentRide;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: GlassContainer(
          borderRadius: 28,
          blur: 24,
          padding: const EdgeInsets.all(20),
          shadows: AppTheme.premiumElevation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Select Payment Method',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: c.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'Cash is the only method available right now. Online payments are not connected yet.',
                style:
                    TextStyle(fontSize: 12, color: c.textMuted, height: 1.35),
              ),
              const SizedBox(height: 14),
              for (final (index, rail) in PaymentRail.values.indexed)
                _paymentOption(context, rail, index, ride, ctx),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentOption(
    BuildContext context,
    PaymentRail rail,
    int index,
    RideModel? ride,
    BuildContext sheetContext,
  ) {
    final c = AppColors.of(context);
    final isSelected = _viewModel.selectedRail == rail;
    final enabled = rail.isConfigured;

    return StaggeredEntryWidget(
      index: index,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.55,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryBlue.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryBlue.withValues(alpha: 0.4)
                  : c.border,
            ),
            boxShadow: isSelected
                ? AppTheme.glowShadow(AppTheme.primaryBlue,
                    opacity: 0.1, blur: 8)
                : null,
          ),
          child: ListTile(
            enabled: enabled,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryBlue
                    : AppTheme.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(rail.icon,
                  color: isSelected ? Colors.white : AppTheme.primaryBlue,
                  size: 18),
            ),
            title: Text(rail.label,
                style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 14,
                    color: c.textPrimary)),
            subtitle: Text(
                enabled
                    ? rail.description
                    : '${rail.description} — not available yet',
                style: TextStyle(fontSize: 11.5, color: c.textMuted)),
            trailing: !enabled
                ? Text('Coming soon',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.textMuted))
                : isSelected
                    ? Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppTheme.emeraldGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            color: Colors.white, size: 14),
                      )
                    : null,
            onTap: !enabled
                ? null
                : () async {
                    _viewModel.selectPaymentMethod(rail);
                    Navigator.pop(sheetContext);
                    if (ride != null) {
                      final rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
                      final ok =
                          await rideProv.setPaymentMethod(ride.id, rail.id);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'We could not save your payment method. It will apply to this trip only.',
                            ),
                            backgroundColor: AppTheme.amberWarning,
                          ),
                        );
                      }
                    }
                  },
          ),
        ),
      ),
    );
  }

  Future<void> _standDownSos(RideProvider rideProv) async {
    final confirmed = await confirmAction(
      context,
      title: "Are you safe?",
      message:
          'This tells your driver and trusted contacts that the emergency is over. Only close it if you are genuinely safe.',
      confirmLabel: "I'm safe",
      destructive: true,
      icon: Icons.health_and_safety_outlined,
    );
    if (!confirmed || !mounted) return;

    final error = await rideProv.resolveActiveSos(note: 'Rider confirmed safe');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            error ?? 'Alert closed. Your contacts will see it is resolved.'),
        backgroundColor:
            error == null ? AppTheme.emeraldGreen : AppTheme.sunsetCoral,
      ),
    );
  }

  Future<void> _offerSosSms(
      List<String> phones, double latitude, double longitude) async {
    if (phones.isEmpty) return;
    final body = 'SwiftRide emergency. I need help. My live location: '
        'https://maps.google.com/?q=$latitude,$longitude';

    var opened = 0;
    for (final phone in phones) {
      final ok = await _viewModel.sendEmergencySms(
        recipientPhone: phone,
        messageText: body,
      );
      if (ok) opened++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened == 0
              ? 'We could not open your messaging app. Call your contacts directly.'
              : 'Message ready for ${opened == 1 ? '1 contact' : '$opened contacts'}. Press send in your messaging app.',
        ),
        backgroundColor:
            opened == 0 ? AppTheme.sunsetCoral : AppTheme.emeraldGreen,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _showSosDialog(
    BuildContext context,
    SafetyProvider safetyProv,
    String rideId,
    String userId,
    double lat,
    double lng,
  ) {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassContainer(
          borderRadius: 24,
          blur: 24,
          padding: const EdgeInsets.all(22),
          shadows: AppTheme.glowShadow(AppTheme.sunsetCoral,
              opacity: 0.35, blur: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PulsingGlowWidget(
                    glowColor: AppTheme.sunsetCoral,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppTheme.sunsetCoral,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Emergency SOS',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: c.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'This sounds an alarm on this device and sends your live location, trip details and driver information to your driver and your trusted contacts through the SwiftRide app. Contacts need the app installed to receive it — you will be told if nobody could be reached.',
                style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.sunsetCoral,
                      side: const BorderSide(color: AppTheme.sunsetCoral),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.local_police, size: 18),
                    label: const Text('Call 15 (Police)'),
                    onPressed: () => _viewModel.callPolice(),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Dismiss',
                            style: TextStyle(
                                color: AppTheme.slateMuted,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.sunsetCoral,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        onPressed: () async {
                          final result = await _viewModel.dispatchSos(
                            safetyProv: safetyProv,
                            rideId: rideId,
                            userId: userId,
                            latitude: lat,
                            longitude: lng,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result.message),
                              backgroundColor: result.reachedAnyone
                                  ? AppTheme.emeraldGreen
                                  : AppTheme.sunsetCoral,
                              duration: Duration(
                                  seconds:
                                      result.reachedAnyone ? 4 : 8),
                              action: result.unreachablePhones.isEmpty
                                  ? null
                                  : SnackBarAction(
                                      label: 'Text them',
                                      textColor: Colors.white,
                                      onPressed: () => _offerSosSms(
                                        result.unreachablePhones,
                                        lat,
                                        lng,
                                      ),
                                    ),
                            ),
                          );
                        },
                        child: const Text('DISPATCH SOS',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}