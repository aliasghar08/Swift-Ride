import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../common/confirm_action.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_status.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../services/ride_service.dart';
import '../../services/firestore/firestore_user_service.dart';
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
  final RideService _rideService = RideService();

  LocationProvider? _locProv;
  RideProvider? _rideProv;
  DateTime _lastTelemetryPublish = DateTime.fromMillisecondsSinceEpoch(0);

  /// Phone number for the rider on the active trip, resolved from their profile.
  String? _riderPhone;
  String? _riderPhoneForRiderId;

  /// Native GPS arrives far more often than we need to write, so throttle.
  static const Duration _telemetryInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _viewModel = DriverViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = CustomChangeNotifierProvider.of<LocationProvider>(context);
    final ride = CustomChangeNotifierProvider.of<RideProvider>(context);
    if (identical(loc, _locProv) && identical(ride, _rideProv)) return;

    _locProv?.onLocationUpdate = null;
    _locProv = loc;
    _rideProv = ride;
    loc.onLocationUpdate = _publishTelemetry;

    // Drivers must see incoming requests: this stream had no subscriber, so a
    // rider's request never reached anyone.
    ride.watchAvailableRides();
  }

  /// Sends the driver's real position to the backend while a trip is active, so
  /// the rider's car marker reflects the actual vehicle instead of the rider's
  /// own GPS.
  void _publishTelemetry(double latitude, double longitude, double heading) {
    final activeRide = _rideProv?.activeRide;
    if (activeRide == null) return;

    final now = DateTime.now();
    if (now.difference(_lastTelemetryPublish) < _telemetryInterval) return;
    _lastTelemetryPublish = now;

    _rideService.publishDriverLocation(
      latitude: latitude,
      longitude: longitude,
      heading: heading,
      activeRideId: activeRide.id,
    );
  }

  /// Loads (once per rider) the phone number to dial for the active trip.
  void _ensureRiderPhone(String? riderId) {
    if (riderId == null || riderId == _riderPhoneForRiderId) return;
    _riderPhoneForRiderId = riderId;
    _riderPhone = null;

    FirestoreUserService().getUser(riderId).then((user) {
      if (!mounted || _riderPhoneForRiderId != riderId) return;
      setState(() => _riderPhone = user?.phone);
    }).catchError((Object e) {
      debugPrint('[DriverHome] rider phone lookup failed: $e');
    });
  }

  @override
  void dispose() {
    _locProv?.onLocationUpdate = null;
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final c = AppColors.of(context);
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    final rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    final locProv = CustomChangeNotifierProvider.of<LocationProvider>(context);
    final authProv = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final currentRide = rideProv.currentRide;
    final driver = driverProv.driverProfile;

    // Resolve the rider's real phone number for the Call Rider action. The
    // button used to dial a hardcoded +92 300 1234567 belonging to nobody.
    _ensureRiderPhone(currentRide?.riderId);

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: c.canvas,
          body: Stack(
            children: [
              // 1. Dark Mode Real Google Maps View
              GoogleMapView(
                initialCenter: LatLng(locProv.latitude, locProv.longitude),
                initialZoom: 15,
                semanticsLabel: currentRide == null
                    ? 'Map of your area. You are online and awaiting requests.'
                    : 'Navigation map. Trip status: ${currentRide.status.displayName}.',
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
                // No surge overlay: this used to draw "high-demand surge zones"
                // as circles anchored to the driver's own position, which was
                // pure decoration presented as demand data. Real surge needs a
                // backend demand aggregation; until that exists we draw nothing
                // rather than imply where the money is.
                polylines: {
                  if (currentRide != null) ...[
                    Polyline(
                      polylineId: const PolylineId('driver_route_casing'),
                      points: [
                        LatLng(locProv.latitude, locProv.longitude),
                        LatLng(currentRide.pickup.latitude, currentRide.pickup.longitude),
                        LatLng(currentRide.dropoff.latitude, currentRide.dropoff.longitude),
                      ],
                      color: AppTheme.primaryNavy,
                      width: 9,
                    ),
                    Polyline(
                      polylineId: const PolylineId('driver_route'),
                      points: [
                        LatLng(locProv.latitude, locProv.longitude),
                        LatLng(currentRide.pickup.latitude, currentRide.pickup.longitude),
                        LatLng(currentRide.dropoff.latitude, currentRide.dropoff.longitude),
                      ],
                      color: AppTheme.amberWarning,
                      width: 5,
                    ),
                  ],
                },
              ),

              // 1b. Active emergency alert on this trip.
              //
              // The backend writes safety_events and pushes to the counterparty,
              // but nothing subscribed: a driver got a notification with no
              // in-app surface and no way to act on it.
              if (rideProv.activeSos != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: layout.horizontalPadding,
                        vertical: layout.scale(8),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
                        child: _buildSosBanner(layout, rideProv, locProv),
                      ),
                    ),
                  ),
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
                                      'Earnings: ${CurrencyFormatter.format(driver.totalEarnings)} • 0% Fee',
                                      style: TextStyle(color: Colors.white70, fontSize: layout.fontSize(12)),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: driverProv.isOnline,
                                activeThumbColor: AppTheme.accentCyan,
                                onChanged: (val) async {
                                  final error = await _viewModel.toggleOnline(
                                    driverProv: driverProv,
                                    locProv: locProv,
                                    online: val,
                                  );
                                  if (error != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(error),
                                        backgroundColor: AppTheme.sunsetCoral,
                                      ),
                                    );
                                  }
                                },
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
                          ? _buildWaitingOrEarningsCard(layout, driver, driverProv, rideProv, authProv)
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

  /// Unmissable banner shown while the rider has an unresolved emergency alert.
  Widget _buildSosBanner(
    ResponsiveLayoutHelper layout,
    RideProvider rideProv,
    LocationProvider locProv,
  ) {
    final sos = rideProv.activeSos!;
    final age = DateTime.now().difference(sos.createdAt);
    final ageLabel = age.inMinutes < 1 ? 'just now' : '${age.inMinutes} min ago';

    return Semantics(
      liveRegion: true,
      label: 'Emergency alert active. The rider triggered SOS $ageLabel.',
      child: Container(
        padding: EdgeInsets.all(layout.scale(14)),
        decoration: BoxDecoration(
          color: AppTheme.sunsetCoral,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.glowShadow(AppTheme.sunsetCoral, opacity: 0.5, blur: 18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.emergency, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'EMERGENCY SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'The rider raised an alert $ageLabel.',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: layout.touchTarget(44),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.sunsetCoral,
                      ),
                      icon: const Icon(Icons.phone, size: 16),
                      label: const Text('Call rider', style: TextStyle(fontSize: 12.5)),
                      onPressed: _riderPhone == null
                          ? null
                          : () => _viewModel.callRider(_riderPhone!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: layout.touchTarget(44),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                      ),
                      icon: const Icon(Icons.local_police, size: 16),
                      label: const Text('Call 15', style: TextStyle(fontSize: 12.5)),
                      onPressed: () => _viewModel.callEmergencyServices(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: layout.touchTarget(40),
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text(
                  'Rider is safe — close alert',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _closeSos(rideProv),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Stands down the open alert after explicit confirmation.
  ///
  /// Confirmed rather than one-tap: closing an emergency alert by accident would
  /// hide a real one. The event is never deleted, so the record survives.
  Future<void> _closeSos(RideProvider rideProv) async {
    final confirmed = await confirmAction(
      context,
      title: 'Close this alert?',
      message:
          'This marks the emergency as resolved for everyone on the trip. Only do '
          'this if the rider has told you they are safe. The incident is still logged.',
      confirmLabel: 'Close alert',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final error = await rideProv.resolveActiveSos(note: 'Closed by driver');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Alert closed. Thank you for confirming.'),
        backgroundColor: error == null ? AppTheme.emeraldGreen : AppTheme.sunsetCoral,
      ),
    );
  }

  Widget _buildWaitingOrEarningsCard(
    ResponsiveLayoutHelper layout,
    DriverProfile driver,
    DriverProvider driverProv,
    RideProvider rideProv,
    AuthProvider authProv,
  ) {
    final requests = driverProv.isOnline ? rideProv.availableRides : const <RideModel>[];

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

        // Incoming ride requests. Without this list a rider's request reached
        // nobody, so no trip could ever be matched.
        if (driverProv.isOnline) ...[
          if (requests.isEmpty)
            Container(
              padding: EdgeInsets.all(layout.scale(12)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      label: 'Waiting for ride requests nearby',
                      child: Text(
                        'Waiting for ride requests nearby…',
                        style: TextStyle(color: Colors.white70, fontSize: layout.fontSize(12)),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final request in requests)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.all(layout.scale(12)),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_taxi, color: AppTheme.accentCyan, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            label:
                                'New ride request for ${CurrencyFormatter.format(request.offeredFare)}',
                            child: Text(
                              'New request • ${CurrencyFormatter.format(request.offeredFare)}',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: layout.fontSize(13),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.pickup.address.isEmpty
                          ? '${request.distanceKm.toStringAsFixed(1)} km trip'
                          : request.pickup.address,
                      style: TextStyle(color: Colors.white70, fontSize: layout.fontSize(11)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: layout.touchTarget(44),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                              onPressed: () => _viewModel.submitCounterOffer(
                                rideProv: rideProv,
                                driver: driver,
                                driverName: authProv.currentUser.fullName,
                                rideId: request.id,
                                fare: request.offeredFare,
                              ),
                              child: Text(
                                'Match ${CurrencyFormatter.format(request.offeredFare)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: layout.touchTarget(44),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentCyan),
                              onPressed: () => _viewModel.submitCounterOffer(
                                rideProv: rideProv,
                                driver: driver,
                                driverName: authProv.currentUser.fullName,
                                rideId: request.id,
                                fare: request.offeredFare + 50.0,
                              ),
                              child: const Text('Counter +50', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          SizedBox(height: layout.scale(12)),
        ],

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
                'Year 1: PKR 0 Fee',
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
            _buildStatBox(layout, 'Saved Fees', CurrencyFormatter.format(driver.totalEarnings * 0.13), Icons.savings_outlined, 2),
          ],
        ),
        SizedBox(height: layout.scale(14)),

        // Withdraw earnings to a Pakistani payout rail.
        SizedBox(
          height: layout.touchTarget(48),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.account_balance_wallet, color: AppTheme.primaryNavy),
            label: Text(
              'Withdraw Earnings (${CurrencyFormatter.format(driverProv.availablePayoutBalance)})',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: AppTheme.primaryNavy,
            ),
            onPressed: _viewModel.isProcessingPayout ||
                    driverProv.availablePayoutBalance <= 0
                ? null
                : () => _showPayoutSheet(driver, driverProv.availablePayoutBalance),
          ),
        ),
      ],
    );
  }

  /// Lets the driver choose a payout rail and destination, then submits to the
  /// backend ledger. Nothing is credited locally — the server owns the balance.
  Future<void> _showPayoutSheet(DriverProfile driver, double availableBalance) async {
    const rails = <({String id, String label, String hint})>[
      (id: 'jazzcash', label: 'JazzCash wallet', hint: 'Mobile number, e.g. 03001234567'),
      (id: 'easypaisa', label: 'Easypaisa wallet', hint: 'Mobile number, e.g. 03451234567'),
      (id: 'raast', label: 'Raast / bank transfer', hint: 'IBAN, e.g. PK36SCBL0000001123456702'),
      (id: 'manual', label: 'Manual settlement', hint: 'Account note for our team'),
    ];

    var selectedRail = rails.first.id;
    final destinationController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = AppColors.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Withdraw ${CurrencyFormatter.format(availableBalance)}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: c.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your final available balance is confirmed by the server.',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                const SizedBox(height: 16),
                for (final rail in rails)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => setSheetState(() => selectedRail = rail.id),
                    leading: Icon(
                      selectedRail == rail.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selectedRail == rail.id ? AppTheme.primaryBlue : c.textMuted,
                    ),
                    title: Text(
                      rail.label,
                      style: TextStyle(fontSize: 14, color: c.textPrimary),
                    ),
                  ),
                const SizedBox(height: 4),
                TextField(
                  controller: destinationController,
                  decoration: InputDecoration(
                    labelText: 'Destination',
                    hintText: rails.firstWhere((r) => r.id == selectedRail).hint,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Request payout'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    final destination = destinationController.text.trim();
    if (destination.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the wallet number or IBAN to pay out to.'),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    final result = await _viewModel.requestPayout(
      amount: availableBalance,
      rail: selectedRail,
      destination: destination,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.accepted ? AppTheme.emeraldGreen : AppTheme.sunsetCoral,
        duration: Duration(seconds: result.accepted ? 4 : 8),
      ),
    );
  }

  Widget _buildStatBox(ResponsiveLayoutHelper layout, String label, String value, IconData icon, int index) {
    final c = AppColors.of(layout.context);
    return Expanded(
      child: StaggeredEntryWidget(
        index: index,
        child: Container(
          padding: EdgeInsets.all(layout.scale(10)),
          decoration: BoxDecoration(
            color: c.surfaceRaised.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
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
              child: Semantics(
                liveRegion: true,
                label: 'Trip status: ${ride.status.displayName}',
                child: Text(
                  ride.status.displayName,
                  style: TextStyle(color: AppTheme.accentCyan, fontWeight: FontWeight.w700, fontSize: layout.fontSize(12)),
                ),
              ),
            ),
            Text(
              'Fare: ${CurrencyFormatter.format(ride.acceptedFare ?? ride.offeredFare)} (0% Fee)',
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
                      driverName: authProv.currentUser.fullName,
                      rideId: ride.id,
                      fare: ride.offeredFare,
                    ),
                    child: Text('Match ${CurrencyFormatter.format(ride.offeredFare)}'),
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
                      driverName: authProv.currentUser.fullName,
                      rideId: ride.id,
                      fare: ride.offeredFare + 50.0,
                    ),
                    child: const Text('Counter +PKR 50'),
                  ),
                ),
              ),
            ],
          ),
        ] else if (ride.status == RideStatus.accepted) ...[
          // Driver on the way to pickup
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: layout.touchTarget(48),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.near_me, color: AppTheme.primaryNavy),
                    label: const Text('Arrived at Pickup'),
                    onPressed: () => _viewModel.signalArrival(rideProv),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: layout.touchTarget(48),
                width: layout.touchTarget(48),
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.accentCyan,
                  ),
                  icon: const Icon(Icons.phone),
                  tooltip: _riderPhone == null ? 'Rider phone unavailable' : 'Call Rider',
                  onPressed: _riderPhone == null
                      ? null
                      : () => _viewModel.callRider(_riderPhone!),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: layout.touchTarget(48),
                width: layout.touchTarget(48),
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.navigation),
                  tooltip: 'Navigate with Google/Apple Maps',
                  onPressed: () => _viewModel.navigateExternally(
                    ride.pickup.latitude,
                    ride.pickup.longitude,
                  ),
                ),
              ),
            ],
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
                        onPressed: () async {
                          final success = await _viewModel.verifyPinAndStartTrip(rideProv);
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
              icon: const Icon(Icons.flag, color: AppTheme.primaryNavy),
              label: const Text('Complete Trip & Settle Fare'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emeraldGreen),
              onPressed: () async {
                await _viewModel.completeActiveTrip(
                  rideProv: rideProv,
                  driverProv: driverProv,
                  authProv: authProv,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    // Not "earnings added" — the rider still has to pay.
                    content: Text('Trip completed. Collect payment from the rider.'),
                    backgroundColor: AppTheme.emeraldGreen,
                  ),
                );
              },
            ),
          ),
        ] else if (ride.status == RideStatus.completed &&
            ride.paymentStatus != 'paid') ...[
          // Cash settlement. Without this the trip stayed unpaid forever: the
          // rider's "Cash" choice was local-only and nothing ever recorded
          // receipt. The amount is derived server-side.
          Container(
            padding: EdgeInsets.all(layout.scale(12)),
            decoration: BoxDecoration(
              color: AppTheme.amberWarning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.amberWarning.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: AppTheme.amberWarning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Collect ${CurrencyFormatter.format(ride.acceptedFare ?? ride.offeredFare)} in cash',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: layout.touchTarget(48),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emeraldGreen),
                    onPressed: _viewModel.isConfirmingCash
                        ? null
                        : () async {
                            final error = await _viewModel.confirmCashPayment(
                              rideProv: rideProv,
                              rideId: ride.id,
                            );
                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error ?? 'Cash payment recorded. Your balance is updated.',
                                ),
                                backgroundColor: error == null
                                    ? AppTheme.emeraldGreen
                                    : AppTheme.sunsetCoral,
                              ),
                            );

                            if (error == null) {
                              await driverProv.loadForUser(authProv.currentUser.id);
                            }
                          },
                    child: _viewModel.isConfirmingCash
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm cash received'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
