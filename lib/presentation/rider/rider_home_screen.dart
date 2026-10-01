import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/models/location_point_model.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_offer_model.dart';
import '../../domain/models/ride_status.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/safety_provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  late final RiderViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = RiderViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loc = CustomChangeNotifierProvider.of<LocationProvider>(context);
      _viewModel.initializeFromCoordinates(loc.latitude, loc.longitude);
    });
  }

  Future<void> _openAddressSearch({required bool isPickup}) async {
    final result = await Navigator.of(context).push<LocationPoint>(
      MaterialPageRoute(
        builder: (_) => AddressSearchScreen(
          title: isPickup ? 'Set Pickup Location' : 'Set Destination',
          initialQuery: isPickup ? _viewModel.pickupController.text : _viewModel.dropoffController.text,
        ),
      ),
    );
    if (result != null) {
      if (isPickup) {
        _viewModel.setPickup(result);
      } else {
        _viewModel.setDropoff(result);
      }
    }
  }

  @override
  void dispose() {
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
    final currentRide = rideProv.currentRide;

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              // 1. Live Google Maps View
              GoogleMapView(
                initialCenter: LatLng(locProv.latitude, locProv.longitude),
                initialZoom: 15,
                mode: _viewModel.isPinMode
                    ? MapMode.pinPicker
                    : (currentRide != null ? MapMode.liveTracking : MapMode.viewOnly),
                darkMode: true,
                showTraffic: true,
                onPinChanged: (coords) => _viewModel.updatePinnedCoordinates(coords.latitude, coords.longitude),
                markers: {
                  if (_viewModel.pickupLocation != null)
                    MapMarkers.pickup(LatLng(_viewModel.pickupLocation!.latitude, _viewModel.pickupLocation!.longitude)),
                  if (_viewModel.dropoffLocation != null)
                    MapMarkers.dropoff(LatLng(_viewModel.dropoffLocation!.latitude, _viewModel.dropoffLocation!.longitude)),
                  if (currentRide != null) ...[
                    MapMarkers.pickup(LatLng(currentRide.pickup.latitude, currentRide.pickup.longitude)),
                    MapMarkers.dropoff(LatLng(currentRide.dropoff.latitude, currentRide.dropoff.longitude)),
                    MapMarkers.driver(
                      driverId: currentRide.driverId ?? 'driver',
                      pos: LatLng(locProv.latitude, locProv.longitude),
                      heading: locProv.heading,
                    ),
                  ],
                },
                polylines: {
                  if (_viewModel.routePolyline.isNotEmpty)
                    Polyline(
                      polylineId: const PolylineId('rider_preview_route'),
                      points: _viewModel.routePolyline,
                      color: AppTheme.accentCyan,
                      width: 5,
                    )
                  else if (currentRide != null)
                    Polyline(
                      polylineId: const PolylineId('rider_active_route'),
                      points: [
                        LatLng(locProv.latitude, locProv.longitude),
                        LatLng(currentRide.pickup.latitude, currentRide.pickup.longitude),
                        LatLng(currentRide.dropoff.latitude, currentRide.dropoff.longitude),
                      ],
                      color: Colors.cyanAccent,
                      width: 5,
                    ),
                },
              ),

              // 2. Top Header Address Search Card (Responsive constraint)
              if (currentRide == null)
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
                        child: _buildAddressCard(layout),
                      ),
                    ),
                  ),
                ),

              // 3. Bottom Sheet (Centered on wide screens / full width on mobile)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                    child: currentRide == null
                        ? _buildFareProposalSheet(layout, rideProv, authProv, driverProv)
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
              // 4. Proactive AI Safety Check Overlay (RideCheck)
              CustomConsumer<SafetyCheckProvider>(
                builder: (context, safetyCheck, _) {
                  if (!safetyCheck.isSafetyActive || safetyCheck.message == null) {
                    return const SizedBox.shrink();
                  }
                  return SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.horizontalPadding,
                            vertical: layout.scale(8),
                          ),
                          child: SafetyCheckOverlay(
                            rideId: safetyCheck.rideId ?? (currentRide?.id ?? 'active_ride'),
                            flagType: safetyCheck.flagType ?? 'SAFETY_CHECK',
                            message: safetyCheck.message!,
                            onDismiss: () => safetyCheck.dismissCheck(),
                            onNeedHelp: () {
                              safetyCheck.triggerEmergencySos();
                              safetyProv.triggerSos();
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
          floatingActionButton: PulsingGlowWidget(
            glowColor: AppTheme.accentCyan,
            minSpread: 1.0,
            maxSpread: 5.0,
            child: FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).pushNamed('/ai-chat'),
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.accentCyan,
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text('Ask AI', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddressCard(ResponsiveLayoutHelper layout) {
    return StaggeredEntryWidget(
      index: 0,
      duration: const Duration(milliseconds: 400),
      child: GlassContainer(
        borderRadius: 20,
        blur: 18,
        padding: EdgeInsets.all(layout.scale(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.radio_button_checked, color: AppTheme.emeraldGreen, size: 20),
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
                    color: _viewModel.isPinMode ? AppTheme.emeraldGreen : AppTheme.primaryBlue,
                  ),
                  tooltip: 'Set Pickup Pin on Map',
                  onPressed: () => _viewModel.togglePinMode(),
                ),
              ],
            ),
            const Divider(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, color: AppTheme.sunsetCoral, size: 20),
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
    );
  }

  Widget _buildFareProposalSheet(
    ResponsiveLayoutHelper layout,
    RideProvider rideProv,
    AuthProvider authProv,
    DriverProvider driverProv,
  ) {
    final suggested = _viewModel.suggestedFare;

    return GlassContainer(
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
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          SizedBox(height: layout.scale(12)),

          // Trip Estimates
          StaggeredEntryWidget(
            index: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Estimated: ${_viewModel.estimatedDistanceKm}km • ${_viewModel.estimatedDurationMin.toInt()} min',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.slateMuted, fontSize: layout.fontSize(12)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Suggested: ${CurrencyFormatter.format(suggested)}',
                    style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700, fontSize: layout.fontSize(12)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: layout.scale(10)),

          // inDrive-style Rider Propose Fare input
          StaggeredEntryWidget(
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Offer (Rider sets the price):',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: layout.fontSize(14)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      height: layout.touchTarget(48),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('PKR', style: TextStyle(fontSize: layout.fontSize(14), fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: layout.touchTarget(48),
                        child: TextField(
                          controller: _viewModel.fareController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(fontSize: layout.fontSize(18), fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: 'Enter fare in PKR',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Quick increment buttons with ergonomic touch sizing
                    SizedBox(
                      height: layout.touchTarget(48),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
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
                          padding: const EdgeInsets.symmetric(horizontal: 10),
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

          // Payment Method selector pill
          StaggeredEntryWidget(
            index: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card, size: 16, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment: ${_viewModel.selectedPaymentMethod}',
                      style: TextStyle(fontSize: layout.fontSize(12), fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showPaymentMethodSheet(context),
                    child: Text(
                      'Change',
                      style: TextStyle(fontSize: layout.fontSize(12), color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: layout.scale(12)),

          // Request Button with glowing elevation
          StaggeredEntryWidget(
            index: 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppTheme.glowShadow(AppTheme.primaryBlue, opacity: 0.35, blur: 16),
              ),
              height: layout.touchTarget(50),
              child: ElevatedButton(
                onPressed: () => _viewModel.submitRideRequest(
                  rideProv: rideProv,
                  authProv: authProv,
                  driverProv: driverProv,
                ),
                child: const Text('Find Nearby Drivers (0% Commission)'),
              ),
            ),
          ),
        ],
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
    return GlassContainer(
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
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          SizedBox(height: layout.scale(10)),

          // Status & 4-Digit PIN Header
          StaggeredEntryWidget(
            index: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sync, color: AppTheme.primaryBlue, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        ride.status.displayName,
                        style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(13),
                        ),
                      ),
                    ],
                  ),
                ),

                // 4-Digit Verification PIN Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.darkNavy,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: AppTheme.glowShadow(AppTheme.accentCyan, opacity: 0.25, blur: 8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: AppTheme.accentCyan, size: 16),
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

          // If still waiting for driver acceptance: show incoming counter-offers
          if (ride.status == RideStatus.requested) ...[
            SizedBox(height: layout.scale(12)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Incoming Driver Offers:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: layout.fontSize(14)),
                ),
                Text(
                  '${offers.length} drivers nearby',
                  style: TextStyle(color: AppTheme.slateMuted, fontSize: layout.fontSize(12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...offers.asMap().entries.map(
                  (entry) => _buildOfferCard(layout, entry.value, rideProv, entry.key),
                ),
            const SizedBox(height: 8),
          ],

          // Active Trip Details
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
                      backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      child: const Icon(Icons.person, color: AppTheme.primaryBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Marcus Vance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: layout.fontSize(13))),
                          Text('Midnight Black Toyota Camry (7XYZ890) • ★ 4.92', style: TextStyle(fontSize: layout.fontSize(11), color: AppTheme.slateMuted)),
                        ],
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(ride.acceptedFare ?? ride.offeredFare),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: layout.fontSize(15), color: AppTheme.emeraldGreen),
                    ),
                  ],
                ),
              ),
            ),
          ],

          SizedBox(height: layout.scale(14)),

          // Ergonomic Action Buttons: Share Trip, SOS Emergency, Cancel
          StaggeredEntryWidget(
            index: 2,
            child: Row(
              children: [
                // Share My Trip
                Expanded(
                  child: SizedBox(
                    height: layout.touchTarget(48),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Share Trip'),
                      onPressed: () {
                        final url = _viewModel.generateShareLink(safetyProv: safetyProv, rideProv: rideProv);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Trip share link generated: $url'),
                            backgroundColor: AppTheme.primaryBlue,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // SOS Emergency Button with Pulsing Glow
                PulsingGlowWidget(
                  glowColor: AppTheme.sunsetCoral,
                  minSpread: 1.0,
                  maxSpread: 5.0,
                  child: SizedBox(
                    height: layout.touchTarget(48),
                    width: layout.touchTarget(48),
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.sunsetCoral.withValues(alpha: 0.18),
                        foregroundColor: AppTheme.sunsetCoral,
                      ),
                      icon: const Icon(Icons.warning_amber_rounded),
                      tooltip: 'Emergency SOS',
                      onPressed: () => _showSosDialog(context, safetyProv, ride.id, authProv.currentUser.id, locProv.latitude, locProv.longitude),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Cancel button
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
                    onPressed: () => rideProv.cancelRide('User cancelled'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(ResponsiveLayoutHelper layout, RideOffer offer, RideProvider rideProv, int index) {
    return StaggeredEntryWidget(
      index: index,
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 8),
        borderRadius: 14,
        blur: 12,
        padding: const EdgeInsets.all(12),
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        borderColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
        shadows: AppTheme.glowShadow(AppTheme.primaryBlue, opacity: 0.08, blur: 10),
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
                      Text(offer.driverName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: layout.fontSize(13))),
                      const SizedBox(width: 6),
                      Text('★ ${offer.driverRating}', style: TextStyle(fontSize: layout.fontSize(11), color: Colors.orange)),
                    ],
                  ),
                  Text(
                    '${offer.vehicleSummary} • ${offer.etaMinutes} min away',
                    style: TextStyle(fontSize: layout.fontSize(11), color: AppTheme.slateMuted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(offer.counterFare),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: layout.fontSize(15), color: AppTheme.primaryBlue),
                ),
                const SizedBox(height: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    backgroundColor: AppTheme.emeraldGreen,
                  ),
                  onPressed: () => _viewModel.acceptDriverOffer(rideProv, offer.id),
                  child: const Text('Accept', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentMethodSheet(BuildContext context) {
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
              const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF0F172A))),
              const SizedBox(height: 14),
              _paymentOption('Credit / Debit Card (Stripe)', Icons.credit_card, 0),
              _paymentOption('Apple Pay (Native PassKit)', Icons.apple, 1),
              _paymentOption('Google Pay (Google Play Services)', Icons.account_balance_wallet, 2),
              _paymentOption('Cash to Driver', Icons.money, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentOption(String title, IconData icon, int index) {
    final isSelected = _viewModel.selectedPaymentMethod == title;
    return StaggeredEntryWidget(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
          ),
          boxShadow: isSelected ? AppTheme.glowShadow(AppTheme.primaryBlue, opacity: 0.1, blur: 8) : null,
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryBlue : AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isSelected ? Colors.white : AppTheme.primaryBlue, size: 18),
          ),
          title: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600, fontSize: 14, color: const Color(0xFF0F172A))),
          trailing: isSelected
              ? Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: AppTheme.emeraldGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                )
              : null,
          onTap: () {
            _viewModel.selectPaymentMethod(title);
            Navigator.pop(context);
          },
        ),
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassContainer(
          borderRadius: 24,
          blur: 24,
          padding: const EdgeInsets.all(22),
          shadows: AppTheme.glowShadow(AppTheme.sunsetCoral, opacity: 0.35, blur: 32),
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
                      child: const Icon(Icons.warning, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Emergency SOS',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'This will immediately dispatch your GPS coordinates, driver details, and live trip tracking to emergency contacts and platform safety operators using native device channels.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Dismiss', style: TextStyle(color: AppTheme.slateMuted, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.sunsetCoral,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onPressed: () async {
                      await _viewModel.dispatchSos(
                        safetyProv: safetyProv,
                        rideId: rideId,
                        userId: userId,
                        latitude: lat,
                        longitude: lng,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('EMERGENCY SOS DISPATCHED: Safety authorities notified via native channel.'),
                            backgroundColor: AppTheme.sunsetCoral,
                          ),
                        );
                      }
                    },
                    child: const Text('DISPATCH SOS', style: TextStyle(fontWeight: FontWeight.w800)),
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
