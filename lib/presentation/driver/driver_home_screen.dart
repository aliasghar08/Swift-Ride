import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_status.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../common/glass_container.dart';
import '../common/google_map_view.dart';
import '../common/map_markers.dart';
import '../common/staggered_animation.dart';
import '../view_models/driver_view_model.dart';
import '../view_models/responsive_layout_helper.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late final DriverViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DriverViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    final rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    final locProv = CustomChangeNotifierProvider.of<LocationProvider>(context);
    final authProv = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final currentRide = rideProv.currentRide;
    final driver = driverProv.driverProfile;

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B0F19),
          body: Stack(
            children: [
              // 1. Dark Mode Real Google Maps View
              GoogleMapView(
                initialCenter: LatLng(locProv.latitude, locProv.longitude),
                initialZoom: 15,
                mode: MapMode.navigation,
                darkMode: true,
                showTraffic: true,
                markers: {
                  MapMarkers.driver(
                    driverId: driver.id,
                    pos: LatLng(locProv.latitude, locProv.longitude),
                    heading: locProv.heading,
                  ),
                  if (currentRide != null) ...[
                    MapMarkers.pickup(LatLng(currentRide.pickup.latitude, currentRide.pickup.longitude)),
                    MapMarkers.dropoff(LatLng(currentRide.dropoff.latitude, currentRide.dropoff.longitude)),
                  ],
                },
                circles: {
                  // Heat map overlay of high-demand surge zones
                  Circle(
                    circleId: const CircleId('surge_zone_downtown'),
                    center: LatLng(locProv.latitude + 0.008, locProv.longitude + 0.006),
                    radius: 750,
                    fillColor: Colors.orange.withValues(alpha: 0.18),
                    strokeColor: Colors.orangeAccent.withValues(alpha: 0.6),
                    strokeWidth: 2,
                  ),
                  Circle(
                    circleId: const CircleId('surge_zone_airport'),
                    center: LatLng(locProv.latitude - 0.012, locProv.longitude - 0.009),
                    radius: 1200,
                    fillColor: Colors.purple.withValues(alpha: 0.14),
                    strokeColor: Colors.purpleAccent.withValues(alpha: 0.5),
                    strokeWidth: 2,
                  ),
                },
                polylines: {
                  if (currentRide != null)
                    Polyline(
                      polylineId: const PolylineId('driver_route'),
                      points: [
                        LatLng(locProv.latitude, locProv.longitude),
                        LatLng(currentRide.pickup.latitude, currentRide.pickup.longitude),
                        LatLng(currentRide.dropoff.latitude, currentRide.dropoff.longitude),
                      ],
                      color: Colors.amberAccent,
                      width: 5,
                    ),
                },
              ),

              // 2. Top Header Bar: Online Switch & Live RTDB Broadcaster
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: layout.horizontalPadding,
                        vertical: layout.scale(8),
                      ),
                      child: StaggeredEntryWidget(
                        index: 0,
                        child: GlassContainer(
                          isDark: true,
                          borderRadius: 20,
                          blur: 20,
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.scale(16),
                            vertical: layout.scale(12),
                          ),
                          shadows: driverProv.isOnline
                              ? AppTheme.glowShadow(AppTheme.emeraldGreen, opacity: 0.25, blur: 16)
                              : AppTheme.darkElevation,
                          child: Row(
                            children: [
                              driverProv.isOnline
                                  ? PulsingGlowWidget(
                                      glowColor: AppTheme.emeraldGreen,
                                      child: const CircleAvatar(
                                        backgroundColor: AppTheme.emeraldGreen,
                                        child: Icon(Icons.drive_eta, color: Colors.white),
                                      ),
                                    )
                                  : CircleAvatar(
                                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                                      child: const Icon(Icons.drive_eta, color: Colors.grey),
                                    ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      driverProv.isOnline ? 'ONLINE (Broadcasting RTDB)' : 'OFFLINE',
                                      style: TextStyle(
                                        color: driverProv.isOnline ? AppTheme.emeraldGreen : Colors.grey,
                                        fontWeight: FontWeight.w800,
                                        fontSize: layout.fontSize(13),
                                      ),
                                    ),
                                    Text(
                                      'Earnings: \$${driver.totalEarnings.toStringAsFixed(2)} • 0% Fee',
                                      style: TextStyle(color: Colors.white70, fontSize: layout.fontSize(12)),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: driverProv.isOnline,
                                activeThumbColor: AppTheme.accentCyan,
                                onChanged: (val) => _viewModel.toggleOnline(
                                  driverProv: driverProv,
                                  locProv: locProv,
                                  online: val,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => Navigator.of(context).pushNamed('/earnings-advisor'),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentTeal.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.accentTeal.withValues(alpha: 0.45)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.psychology, size: 14, color: AppTheme.accentTeal),
                                      SizedBox(width: 4),
                                      Text(
                                        'AI',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.accentTeal,
                                        ),
                                      ),
                                    ],
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
              ),

              // 3. Bottom Cockpit Card
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                    child: GlassContainer(
                      isDark: true,
                      borderRadius: 28,
                      blur: 24,
                      shadows: AppTheme.darkElevation,
                      padding: EdgeInsets.fromLTRB(
                        layout.horizontalPadding,
                        14,
                        layout.horizontalPadding,
                        layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 20,
                      ),
                      child: currentRide == null
                          ? _buildWaitingOrEarningsCard(layout, driver, driverProv)
                          : _buildActiveDriverRideCard(layout, currentRide, rideProv, driverProv, authProv),
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: PulsingGlowWidget(
            glowColor: AppTheme.accentCyan,
            minSpread: 1.0,
            maxSpread: 5.0,
            child: FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).pushNamed('/ai-chat'),
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.accentCyan,
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text('AI Assistant', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaitingOrEarningsCard(
    ResponsiveLayoutHelper layout,
    DriverProfile driver,
    DriverProvider driverProv,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        SizedBox(height: layout.scale(12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Driver Dashboard',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: layout.fontSize(16)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Year 1: \$0 Fee',
                style: TextStyle(color: AppTheme.emeraldGreen, fontWeight: FontWeight.w700, fontSize: layout.fontSize(11)),
              ),
            ),
          ],
        ),
        SizedBox(height: layout.scale(12)),

        // Quick Stats Row
        Row(
          children: [
            _buildStatBox(layout, 'Total Rides', '${driver.totalRides}', Icons.check_circle_outline, 0),
            const SizedBox(width: 8),
            _buildStatBox(layout, 'Rating', '★ ${driver.rating}', Icons.star_border, 1),
            const SizedBox(width: 8),
            _buildStatBox(layout, 'Saved Fees', '\$${(driver.totalEarnings * 0.13).toStringAsFixed(0)}', Icons.savings_outlined, 2),
          ],
        ),
        SizedBox(height: layout.scale(14)),

        // Stripe Instant Payout Button (minimum 48px height)
        SizedBox(
          height: layout.touchTarget(48),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.flash_on, color: Color(0xFF0A1128)),
            label: Text('Instant Payout to Card (\$${driver.totalEarnings.toStringAsFixed(2)})'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: const Color(0xFF0A1128),
            ),
            onPressed: () async {
              final result = await _viewModel.requestInstantPayout(driverProv);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Stripe Instant Payout (${result.transactionId}) processed to debit card.',
                    ),
                    backgroundColor: AppTheme.emeraldGreen,
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(ResponsiveLayoutHelper layout, String label, String value, IconData icon, int index) {
    return Expanded(
      child: StaggeredEntryWidget(
        index: index,
        child: Container(
          padding: EdgeInsets.all(layout.scale(10)),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.accentCyan, size: layout.scale(18)),
              const SizedBox(height: 6),
              Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: layout.fontSize(14))),
              Text(label, style: TextStyle(color: Colors.white60, fontSize: layout.fontSize(10))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveDriverRideCard(
    ResponsiveLayoutHelper layout,
    RideModel ride,
    RideProvider rideProv,
    DriverProvider driverProv,
    AuthProvider authProv,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        SizedBox(height: layout.scale(10)),

        // Ride Status Banner
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentCyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ride.status.displayName,
                style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.w700, fontSize: layout.fontSize(12)),
              ),
            ),
            Text(
              'Fare: \$${(ride.acceptedFare ?? ride.offeredFare).toStringAsFixed(2)} (0% Fee)',
              style: TextStyle(color: AppTheme.emeraldGreen, fontWeight: FontWeight.w800, fontSize: layout.fontSize(15)),
            ),
          ],
        ),
        SizedBox(height: layout.scale(10)),

        // Pickup / Dropoff text
        Text(
          'Pickup: ${ride.pickup.address}',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: layout.fontSize(13)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          'Dropoff: ${ride.dropoff.address}',
          style: TextStyle(color: Colors.white70, fontSize: layout.fontSize(12)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: layout.scale(12)),

        // Status Lifecycle Controls
        if (ride.status == RideStatus.requested) ...[
          // Incoming request: Driver can submit counter-offer or accept rider proposed fare
          Text('Counter-Offer (inDrive Bidding):', style: TextStyle(color: Colors.white70, fontSize: layout.fontSize(12))),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: layout.touchTarget(48),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => _viewModel.submitCounterOffer(
                      rideProv: rideProv,
                      driver: driverProv.driverProfile,
                      rideId: ride.id,
                      fare: ride.offeredFare,
                    ),
                    child: Text('Match \$${ride.offeredFare.toStringAsFixed(2)}'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: layout.touchTarget(48),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentCyan),
                    onPressed: () => _viewModel.submitCounterOffer(
                      rideProv: rideProv,
                      driver: driverProv.driverProfile,
                      rideId: ride.id,
                      fare: ride.offeredFare + 2.0,
                    ),
                    child: const Text('Counter +\$2.00'),
                  ),
                ),
              ),
            ],
          ),
        ] else if (ride.status == RideStatus.accepted) ...[
          // Driver on the way to pickup
          SizedBox(
            height: layout.touchTarget(48),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.near_me, color: Color(0xFF0A1128)),
              label: const Text('Arrived at Pickup Location'),
              onPressed: () => _viewModel.signalArrival(rideProv),
            ),
          ),
        ] else if (ride.status == RideStatus.driverArrived) ...[
          // Arrived: Driver enters rider's 4-digit PIN to start trip
          GlassContainer(
            isDark: true,
            borderRadius: 16,
            blur: 16,
            padding: const EdgeInsets.all(12),
            shadows: AppTheme.glowShadow(AppTheme.accentCyan, opacity: 0.15, blur: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin, color: AppTheme.accentCyan, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Ask Rider for 4-Digit Verification PIN:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: layout.fontSize(12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: layout.touchTarget(48),
                        child: TextField(
                          controller: _viewModel.pinController,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: layout.fontSize(18), letterSpacing: 8, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'PIN',
                            hintStyle: TextStyle(color: Colors.white30, letterSpacing: 4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: layout.touchTarget(48),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emeraldGreen),
                        onPressed: () {
                          final success = _viewModel.verifyPinAndStartTrip(rideProv);
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_viewModel.pinErrorMessage ?? 'Invalid verification PIN.'),
                                backgroundColor: AppTheme.sunsetCoral,
                              ),
                            );
                          }
                        },
                        child: const Text('Start Trip'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else if (ride.status == RideStatus.inProgress) ...[
          // In Progress: Driver finishes trip
          SizedBox(
            height: layout.touchTarget(48),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.flag, color: Color(0xFF0A1128)),
              label: const Text('Complete Trip & Settle Fare'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emeraldGreen),
              onPressed: () {
                _viewModel.completeActiveTrip(
                  rideProv: rideProv,
                  driverProv: driverProv,
                  authProv: authProv,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Trip Completed! Fare settled to your balance at 0% platform fee.'),
                    backgroundColor: AppTheme.emeraldGreen,
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
