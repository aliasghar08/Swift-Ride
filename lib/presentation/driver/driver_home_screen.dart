import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/native/native_channel_constants.dart';
import '../../core/constants/app_constants.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../common/ai_consent_dialog.dart';
import '../common/confirm_action.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/trip_economics_model.dart';
import '../../domain/models/vehicle_type.dart';
import '../widgets/trip_economics_sheet.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../services/ride_service.dart';
import '../../services/firestore/firestore_user_service.dart';

import '../common/glass_container.dart';
import '../common/prominent_disclosure_dialog.dart';
import '../common/google_map_view.dart';
import '../common/map_markers.dart';
import '../common/reserved_bottom_ad_bar.dart';
import '../common/staggered_animation.dart';
import '../rider/route_preview_screen.dart';
import '../../services/map_service.dart';
import '../view_models/driver_view_model.dart';
import '../view_models/responsive_layout_helper.dart';
import '../../services/driver_khata_service.dart';
import 'widgets/driver_khata_sheet.dart';
import '../common/exact_change_dialog.dart';
import '../../services/route_corridor_service.dart';
import 'widgets/driver_analytics_drawer.dart';
import 'widgets/driver_name_dialog.dart';
import 'widgets/driver_status_credibility_dialog.dart';
import 'driver_verification_screen.dart';
import '../../domain/models/demand_hotspot_model.dart';
import '../../services/firestore/firestore_ride_service.dart';
import '../../domain/models/user_role.dart';
import '../../services/ad_service.dart';
import '../../services/native/native_storage_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/ride_chat_service.dart';
import '../widgets/ride_chat_sheet.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasCheckedDriverName = false;
  bool _isWomenDriverPromoDismissed = false;
  bool _isCredibilityCardDismissed = false;
  late final DriverViewModel _viewModel;
  final RideService _rideService = RideService();

  LocationProvider? _locProv;
  RideProvider? _rideProv;
  DateTime _lastTelemetryPublish = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastPublishedLat = 0.0;
  double _lastPublishedLng = 0.0;
  bool? _lastReportedHasActiveRide;
  GoogleMapController? _mapController;
  bool _isMapPanned = false;
  bool _is3DNavigationMode = true;
  bool _showTraffic = true;

  /// Phone number for the rider on the active trip, resolved from their profile.
  String? _riderPhone;
  String? _riderPhoneForRiderId;

  /// Native GPS arrives far more often than we need to write, so throttle.
  static const Duration _telemetryInterval = Duration(seconds: 4);
  bool _hasCheckedAutoOnline = false;
  StreamSubscription<List<DemandHotspot>>? _hotspotSub;
  DateTime _lastMovedTime = DateTime.now();
  double _lastStationaryLat = 0.0;
  double _lastStationaryLng = 0.0;

  @override
  void initState() {
    super.initState();
    _viewModel = DriverViewModel();
    _hotspotSub = FirestoreRideService().streamDemandHotspots().listen((hotspots) {
      if (mounted) {
        _viewModel.setDemandHotspots(hotspots);
        setState(() {});
      }
    });
    NativeStorageService().getBool('promo_dismissed_women_driver_mode_v1').then((val) {
      if (mounted && val == true) {
        setState(() => _isWomenDriverPromoDismissed = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = CustomChangeNotifierProvider.of<LocationProvider>(context);
    final ride = CustomChangeNotifierProvider.of<RideProvider>(context);

    if (!_hasCheckedDriverName) {
      _hasCheckedDriverName = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
        final user = auth.currentUser;
        final isDriverAccount = auth.activeRole == UserRole.driver &&
            (user.phone.isNotEmpty || auth.isAuthenticated);
        if (isDriverAccount && isDefaultDriverName(user.fullName)) {
          DriverNameDialog.show(
            context,
            currentName: user.fullName,
            barrierDismissible: false,
          );
        }
      });
    }

    if (!_hasCheckedAutoOnline) {
      _hasCheckedAutoOnline = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
        final locProv = CustomChangeNotifierProvider.of<LocationProvider>(context);
        await _ensureDriverAutoOnline(driverProv, locProv);
      });
    }

    if (identical(loc, _locProv) && identical(ride, _rideProv)) return;

    _locProv?.onLocationUpdate = null;
    _locProv = loc;
    _rideProv = ride;
    loc.onLocationUpdate = _publishTelemetry;

    // Drivers must see incoming requests: watch stream for matching
    ride.watchAvailableRides();
  }

  /// Automatically transitions verified drivers to Online unless explicitly toggled offline.
  Future<void> _ensureDriverAutoOnline(
    DriverProvider driverProv,
    LocationProvider locProv,
  ) async {
    final driver = driverProv.driverProfile;
    if (AppConstants.kRequireDriverVerification) {
      final isVerified = driver.isVerified || driverProv.hasPassedAiVerification;
      if (!isVerified) return;
    }
    if (!driver.vehicle.isConfigured) return;

    final storage = NativeStorageService();
    final explicitlyOffline = await storage.getBool('driver_explicitly_offline') ?? false;
    if (explicitlyOffline) return;

    if (!driverProv.isOnline) {
      final hasForeground = await locProv.permissionStatus();
      if (hasForeground != true) {
        if (!mounted) return;
        final granted = await PermissionDisclosures.ensureForegroundLocation(
          context,
          asDriver: true,
        );
        if (!granted && mounted && await locProv.permissionStatus() == false) {
          return;
        }
      }

      if (mounted) {
        await PermissionDisclosures.ensureBackgroundLocation(context);
      }

      if (!mounted) return;
      await _viewModel.toggleOnline(
        driverProv: driverProv,
        locProv: locProv,
        online: true,
      );

      // Sync FCM token
      final token = await FirebaseMessaging.instance.getToken().catchError((_) => null);
      if (token != null) {
        await PushNotificationService.instance.syncTokenToFirestore(token);
      }
    }
  }

  /// Sends the driver's real position to the backend while a trip is active
  /// and smoothly follows the vehicle in 3D perspective mode.
  /// Throttled by both distance (>= 10m) and time (>= 4s) to avoid redundant radio wakeups.
  void _publishTelemetry(double latitude, double longitude, double heading) {
    final activeRide = _rideProv?.activeRide;
    final hasActiveRide = activeRide != null;
    if (_lastReportedHasActiveRide != hasActiveRide) {
      _lastReportedHasActiveRide = hasActiveRide;
      MethodChannel(NativeChannelConstants.locationChannel).invokeMethod(
        NativeChannelConstants.methodSetHasActiveRide,
        {'hasActiveRide': hasActiveRide},
      ).catchError((_) => null);
    }

    if (activeRide != null) {
      final now = DateTime.now();
      final distMeters = _lastPublishedLat == 0.0
          ? 999.0
          : GeohashUtil.distanceKm(_lastPublishedLat, _lastPublishedLng, latitude, longitude) * 1000.0;
      final timeElapsed = now.difference(_lastTelemetryPublish) >= _telemetryInterval;

      // Throttle: upload if driver moved >= 10 meters OR if >= 4s elapsed AND moved >= 2m
      if ((distMeters >= 10.0 && now.difference(_lastTelemetryPublish) >= const Duration(seconds: 2)) ||
          (timeElapsed && distMeters >= 2.0)) {
        _lastTelemetryPublish = now;
        _lastPublishedLat = latitude;
        _lastPublishedLng = longitude;
        _rideService.publishDriverLocation(
          latitude: latitude,
          longitude: longitude,
          heading: heading,
          activeRideId: activeRide.id,
        );
      }
    } else {
      // Track stationary duration and evaluate repositioning nudges when waiting
      final now = DateTime.now();
      final distFromStationary = _lastStationaryLat == 0.0
          ? 0.0
          : GeohashUtil.distanceKm(_lastStationaryLat, _lastStationaryLng, latitude, longitude) * 1000.0;
      if (distFromStationary >= 20.0 || _lastStationaryLat == 0.0) {
        _lastStationaryLat = latitude;
        _lastStationaryLng = longitude;
        _lastMovedTime = now;
      }
      final idleDuration = now.difference(_lastMovedTime);
      final driverProv = CustomChangeNotifierProvider.maybeOf<DriverProvider>(context);
      if (driverProv != null) {
        _viewModel.evaluateRepositioningNudge(
          currentLat: latitude,
          currentLng: longitude,
          isOnline: driverProv.isOnline,
          idleDuration: idleDuration,
        );
      }
    }

    // Dynamic 3D camera navigation follow
    if (!_isMapPanned && _mapController != null) {
      if (activeRide != null && _is3DNavigationMode) {
        _mapController?.followNavigation(
          target: LatLng(latitude, longitude),
          bearing: heading,
          zoom: 17.5,
          tilt: 50.0,
        );
      } else {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(latitude, longitude),
              zoom: activeRide != null ? 16.5 : 15.0,
              bearing: _is3DNavigationMode ? heading : 0.0,
              tilt: (_is3DNavigationMode && activeRide != null) ? 45.0 : 0.0,
            ),
          ),
        );
      }
    }
  }

  /// Loads (once per rider) the phone number to dial for the active trip.
  void _ensureRiderPhone(String? riderId) {
    if (riderId == null || riderId == _riderPhoneForRiderId) return;
    _riderPhoneForRiderId = riderId;
    _riderPhone = null;

    FirestoreUserService()
        .getUser(riderId)
        .then((user) {
          if (!mounted || _riderPhoneForRiderId != riderId) return;
          setState(() => _riderPhone = user?.phone);
        })
        .catchError((Object e) {
          debugPrint('[DriverHome] rider phone lookup failed: $e');
        });
  }

  void _showVehicleSetupRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(
          Icons.directions_car_filled_rounded,
          size: 40,
          color: AppTheme.amberWarning,
        ),
        title: const Text(
          'Add Vehicle Details to Go Online',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: const Text(
          'Please provide your vehicle details (category, make/model, number plate, and color) to start receiving ride requests. Document verification is optional and can be completed anytime.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DriverVerificationScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Add Vehicle Details'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hotspotSub?.cancel();
    _locProv?.onLocationUpdate = null;
    _viewModel.dispose();
    super.dispose();
  }

  void _showDriverCustomFareSheet({
    required BuildContext context,
    required RideProvider rideProv,
    required DriverProfile driver,
    required String driverName,
    required String rideId,
    required double initialFare,
    double? costFloor,
  }) {
    // Check race condition upfront
    final isStillAvailable = rideProv.incomingRequests.any((r) => r.id == rideId) ||
        rideProv.activeRide?.id == rideId;
    if (!isStillAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This ride request is no longer available.'),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    final initialClamped = initialFare.clamp(50.0, 50000.0).round();
    final controller = TextEditingController(text: initialClamped.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = AppColors.of(ctx);
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final rawText = controller.text.trim();
            final parsedFare = (double.tryParse(rawText) ?? initialFare).clamp(50.0, 50000.0);
            final commission = (parsedFare * 0.02).round();
            final netEarnings = (parsedFare * 0.98).round();

            void adjust(double delta) {
              final cur = double.tryParse(controller.text) ?? initialFare;
              final next = (cur + delta).round().clamp(50, 50000);
              controller.text = next.toString();
              setModalState(() {});
            }

            return Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: c.border),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                    top: 20,
                    left: 20,
                    right: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Your Custom Counter-Offer',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.primaryNavy,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You have full control over your fare. Type any amount (PKR 50 - 50,000) or use quick steppers.',
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.surfaceRaised,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'PKR',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.primaryNavy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.primaryNavy,
                              ),
                              onChanged: (val) {
                                if (val.length > 1 && val.startsWith('0')) {
                                  final stripped = val.replaceFirst(RegExp(r'^0+'), '');
                                  controller.value = TextEditingValue(
                                    text: stripped,
                                    selection: TextSelection.collapsed(offset: stripped.length),
                                  );
                                }
                                setModalState(() {});
                              },
                              decoration: InputDecoration(
                                hintText: 'Enter fare (50 - 50,000)',
                                filled: true,
                                fillColor: c.surfaceRaised,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: () => adjust(-100),
                            child: const Text('-100'),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => adjust(-50),
                            child: const Text('-50'),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => adjust(50),
                            child: const Text('+50'),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => adjust(100),
                            child: const Text('+100'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.surfaceRaised,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '2% Platform Fee',
                                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                                ),
                                Text(
                                  'PKR $commission',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Your Net Take-Home (98%)',
                                  style: TextStyle(fontSize: 12, color: AppTheme.emeraldGreen),
                                ),
                                Text(
                                  'PKR $netEarnings',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.emeraldGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (costFloor != null && parsedFare < costFloor) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade700),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Below cost floor of PKR ${costFloor.toInt()} (Fuel + Wear + 18%). You may operate at a loss.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentCyan,
                            foregroundColor: AppTheme.primaryNavy,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            final stillPending = rideProv.incomingRequests.any((r) => r.id == rideId) ||
                                rideProv.activeRide?.id == rideId;
                            if (!stillPending) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ride request was cancelled or accepted by another driver.'),
                                  backgroundColor: AppTheme.sunsetCoral,
                                ),
                              );
                              return;
                            }

                            final val = double.tryParse(controller.text) ?? initialFare;
                            final sanitizedFare = val.clamp(50.0, 50000.0);

                            Navigator.of(ctx).pop();
                            _viewModel.submitCounterOffer(
                              rideProv: rideProv,
                              driver: driver,
                              driverName: driverName,
                              rideId: rideId,
                              fare: sanitizedFare,
                            );
                          },
                          child: Text(
                            'Send Counter-Offer (PKR ${(double.tryParse(controller.text) ?? initialFare).clamp(50.0, 50000.0).round()})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    final rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    final locProv = CustomChangeNotifierProvider.of<LocationProvider>(context);
    final authProv = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final currentRide = rideProv.currentRide;
    final driver = driverProv.driverProfile;

    _ensureRiderPhone(currentRide?.riderId);

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          key: _scaffoldKey,
          drawer: const DriverAnalyticsDrawer(),
          backgroundColor: c.canvas,
          bottomNavigationBar: const ReservedBottomAdBar(),
          body: Stack(
            children: [
              // 1. Dark Mode Real Google Maps View with Live Navigation
              Listener(
                onPointerDown: (_) {
                  if (!_isMapPanned) {
                    setState(() => _isMapPanned = true);
                  }
                },
                child: GoogleMapView(
                  initialCenter: LatLng(locProv.latitude, locProv.longitude),
                  initialZoom: 15,
                  semanticsLabel: currentRide == null
                      ? 'Map of your area. You are online and awaiting requests.'
                      : 'Navigation map. Trip status: ${currentRide.status.displayName}.',
                  mode: MapMode.navigation,
                  darkMode: true,
                  showTraffic: _showTraffic,
                  circles: _buildDemandCircles(),
                  onControllerCreated: (controller) {
                    _mapController = controller;
                  },
                  markers: {
                    MapMarkers.driver(
                      driverId: driver.id,
                      pos: LatLng(locProv.latitude, locProv.longitude),
                      heading: locProv.heading,
                    ),
                    if (currentRide != null) ...[
                      MapMarkers.pickup(
                        LatLng(
                          currentRide.pickup.latitude,
                          currentRide.pickup.longitude,
                        ),
                        id: 'driver_ride_pickup',
                      ),
                      MapMarkers.dropoff(
                        LatLng(
                          currentRide.dropoff.latitude,
                          currentRide.dropoff.longitude,
                        ),
                        id: 'driver_ride_dropoff',
                      ),
                      ...currentRide.waypoints
                          .where((w) => w['completed'] != true && w['lat'] != null && w['lng'] != null)
                          .map((w) {
                        final isPickup = w['type'] == 'pickup';
                        final lat = (w['lat'] as num).toDouble();
                        final lng = (w['lng'] as num).toDouble();
                        final wId = 'waypoint_${w['rideId']}_${w['type']}';
                        return isPickup
                            ? MapMarkers.pickup(LatLng(lat, lng), id: wId)
                            : MapMarkers.dropoff(LatLng(lat, lng), id: wId);
                      }),
                    ],
                  },
                  polylines: {
                    if (currentRide != null) ...[
                      ...() {
                        final cachedPlan =
                            _viewModel.getCachedRoutePlan(currentRide.id);
                        if (cachedPlan == null) {
                          _viewModel.getOrFetchRoute(currentRide);
                        }
                        final route = cachedPlan?.routes.firstOrNull;
                        final routePoints = route?.polylinePoints;
                        final points = (routePoints != null &&
                                routePoints.isNotEmpty)
                            ? routePoints
                            : [
                                LatLng(locProv.latitude, locProv.longitude),
                                LatLng(
                                  currentRide.pickup.latitude,
                                  currentRide.pickup.longitude,
                                ),
                                LatLng(
                                  currentRide.dropoff.latitude,
                                  currentRide.dropoff.longitude,
                                ),
                              ];

                        final intervals =
                            route?.trafficIntervals ?? const <TrafficInterval>[];

                        return [
                          Polyline(
                            polylineId: const PolylineId('driver_route_casing'),
                            points: points,
                            color: AppTheme.primaryNavy,
                            width: 14,
                            jointType: JointType.round,
                            startCap: Cap.roundCap,
                            endCap: Cap.roundCap,
                            geodesic: false,
                            zIndex: 0,
                          ),
                          Polyline(
                            polylineId: const PolylineId('driver_route_fill'),
                            points: points,
                            color: AppTheme.accentCyan,
                            width: 9,
                            jointType: JointType.round,
                            startCap: Cap.roundCap,
                            endCap: Cap.roundCap,
                            geodesic: false,
                            zIndex: 1,
                          ),
                          if (_showTraffic && intervals.isNotEmpty)
                            ...TrafficInterval.segment(points, intervals)
                                .asMap()
                                .entries
                                .map((entry) {
                              final interval = entry.value.interval;
                              final isJam = interval?.isJam == true;
                              final isSlow = interval?.isSlow == true;
                              final color = isJam
                                  ? AppTheme.sunsetCoral
                                  : (isSlow
                                      ? AppTheme.amberWarning
                                      : AppTheme.emeraldGreen);
                              return Polyline(
                                polylineId: PolylineId(
                                  'driver_route_traffic_${entry.key}',
                                ),
                                points: entry.value.points,
                                color: color,
                                width: 9,
                                jointType: JointType.round,
                                startCap: Cap.roundCap,
                                endCap: Cap.roundCap,
                                geodesic: false,
                                zIndex: 2,
                              );
                            }),
                        ];
                      }(),
                    ],
                  },
                ),
              ),

              // 1b. Active emergency alert banner
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
                        constraints: BoxConstraints(
                          maxWidth: layout.maxCardWidth,
                        ),
                        child: _buildSosBanner(layout, rideProv, locProv),
                      ),
                    ),
                  ),
                ),

              // 2. Live Navigation HUD when active trip, or Top Header Bar
              if (currentRide != null) ...[
                () {
                  final cachedPlan =
                      _viewModel.getCachedRoutePlan(currentRide.id);
                  final route = cachedPlan?.routes.firstOrNull;
                  final isEnRouteToDropoff =
                      currentRide.status == RideStatus.inProgress ||
                          currentRide.status == RideStatus.driverArrived;
                  final targetName = isEnRouteToDropoff
                      ? currentRide.dropoff.address
                      : currentRide.pickup.address;

                  return LiveNavigationHud(
                    isDriver: true,
                    activeRoute: route,
                    currentVehicleLocation:
                        LatLng(locProv.latitude, locProv.longitude),
                    currentSpeedKmh: (locProv.speed * 3.6).clamp(0.0, 160.0),
                    heading: locProv.heading,
                    destinationAddress: targetName,
                    remainingDistanceKm: route?.distanceKm ?? 2.5,
                    remainingDurationMin: route?.durationMin ?? 6.0,
                    isMapPanned: _isMapPanned,
                    is3DMode: _is3DNavigationMode,
                    isTrafficLayerActive: _showTraffic,
                    onRecenter: () {
                      setState(() => _isMapPanned = false);
                      if (_is3DNavigationMode) {
                        _mapController?.followNavigation(
                          target: LatLng(locProv.latitude, locProv.longitude),
                          bearing: locProv.heading,
                          zoom: 17.5,
                          tilt: 50.0,
                        );
                      } else {
                        _mapController?.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target:
                                  LatLng(locProv.latitude, locProv.longitude),
                              zoom: 16.5,
                              bearing: 0.0,
                              tilt: 0.0,
                            ),
                          ),
                        );
                      }
                    },
                    onToggle3D: (is3D) {
                      setState(() => _is3DNavigationMode = is3D);
                      if (_is3DNavigationMode) {
                        _mapController?.followNavigation(
                          target: LatLng(locProv.latitude, locProv.longitude),
                          bearing: locProv.heading,
                          zoom: 17.5,
                          tilt: 50.0,
                        );
                      } else {
                        _mapController?.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target:
                                  LatLng(locProv.latitude, locProv.longitude),
                              zoom: 16.5,
                              bearing: 0.0,
                              tilt: 0.0,
                            ),
                          ),
                        );
                      }
                    },
                    onToggleTraffic: (trafficActive) {
                      setState(() => _showTraffic = trafficActive);
                    },
                  );
                }(),
              ] else
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_shouldShowWomenDriverPromo(driver))
                              _buildWomenDriverPromoBanner(
                                layout: layout,
                                driver: driver,
                                driverProv: driverProv,
                                isDark: isDark,
                              ),
                            if (_shouldShowCredibilityCard(driver, driverProv))
                              _buildCredibilityCard(
                                layout: layout,
                                c: c,
                                isDark: isDark,
                              ),
                            GlassContainer(
                              borderRadius: 18,
                              blur: 20,
                              padding: EdgeInsets.symmetric(
                                horizontal: layout.scale(12),
                                vertical: layout.isHeightCompact ? 8 : layout.scale(10),
                              ),
                              shadows: driverProv.isOnline
                                  ? AppTheme.glowShadow(
                                      AppTheme.emeraldGreen,
                                      opacity: 0.25,
                                      blur: 16,
                                    )
                                  : (isDark ? AppTheme.darkElevation : AppTheme.subtleElevation),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.menu_rounded,
                                        color: AppTheme.emeraldGreen,
                                        size: 17,
                                      ),
                                    ),
                                  ),
                                  driverProv.isOnline
                                      ? PulsingGlowWidget(
                                          glowColor: AppTheme.emeraldGreen,
                                          child: CircleAvatar(
                                            radius: layout.isHeightCompact ? 14 : 16,
                                            backgroundColor: AppTheme.emeraldGreen,
                                            child: const Icon(
                                              Icons.drive_eta,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        )
                                      : CircleAvatar(
                                          radius: layout.isHeightCompact ? 14 : 16,
                                          backgroundColor: Colors.grey.withValues(
                                            alpha: 0.2,
                                          ),
                                          child: const Icon(
                                            Icons.drive_eta,
                                            color: Colors.grey,
                                            size: 16,
                                          ),
                                        ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          driverProv.isOnline
                                              ? 'ONLINE (Broadcasting RTDB)'
                                              : 'OFFLINE',
                                          style: TextStyle(
                                            color: driverProv.isOnline
                                                ? AppTheme.emeraldGreen
                                                : Colors.grey,
                                            fontWeight: FontWeight.w800,
                                            fontSize: layout.fontSize(12),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'Earnings: ${CurrencyFormatter.format(driver.totalEarnings)} • 2% Fee',
                                          style: TextStyle(
                                            color: isDark ? Colors.white70 : c.textMuted,
                                            fontSize: layout.fontSize(11),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Transform.scale(
                                    scale: 0.85,
                                    child: Switch(
                                      value: driverProv.isOnline,
                                      activeThumbColor: AppTheme.accentCyan,
                                      onChanged: (val) async {
                                        if (!val) {
                                          // Switching OFF: show credibility & status confirmation first
                                          final confirmed = await DriverStatusCredibilityDialog.show(
                                            context,
                                            isGoingOnline: false,
                                          );
                                          if (confirmed != true || !context.mounted) {
                                            return;
                                          }
                                        } else {
                                          if (!driver.vehicle.isConfigured) {
                                            _showVehicleSetupRequiredDialog(context);
                                            return;
                                          }

                                          // 1. Foreground Location Prominent Disclosure -> OS runtime prompt
                                          final granted = await PermissionDisclosures
                                              .ensureForegroundLocation(
                                            context,
                                            asDriver: true,
                                          );
                                          if (!context.mounted) return;
                                          if (!granted &&
                                              await locProv.permissionStatus() ==
                                                  false) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Location access is required to go online. You can enable it in your device Settings.',
                                                ),
                                              ),
                                            );
                                            return;
                                          }

                                          // 2. Background Location Prominent Disclosure -> OS runtime prompt ("Allow all the time")
                                          if (!context.mounted) return;
                                          await PermissionDisclosures
                                              .ensureBackgroundLocation(context);
                                          if (!context.mounted) return;
                                        }
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
                                              action: !driver.vehicle.isConfigured
                                                  ? SnackBarAction(
                                                      label: 'Setup Vehicle',
                                                      textColor: Colors.white,
                                                      onPressed: () {
                                                        Navigator.of(context).push(
                                                          MaterialPageRoute(
                                                            builder: (_) => const DriverVerificationScreen(),
                                                          ),
                                                        );
                                                      },
                                                    )
                                                  : null,
                                            ),
                                          );
                                        } else if (error == null &&
                                            val &&
                                            context.mounted) {
                                          await PermissionDisclosures
                                              .ensureNotifications(context);
                                          if (context.mounted) {
                                            DriverStatusCredibilityDialog.show(
                                              context,
                                              isGoingOnline: true,
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: layout.isHeightCompact ? 6 : 8),
                              // Streamlined Horizontal Quick Actions Row
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  children: [
                                    // Women Only Toggle Pill
                                    InkWell(
                                      onTap: () async {
                                        final error = await _viewModel.toggleFemalePassengersOnly(
                                          driverProv: driverProv,
                                          enabled: !driverProv.femalePassengersOnly,
                                        );
                                        if (error != null && context.mounted) {
                                          _showWomenOnlyDriverGatingDialog(context, error, driver);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                        decoration: BoxDecoration(
                                          color: driverProv.femalePassengersOnly
                                              ? const Color(0xFFE91E63).withValues(alpha: 0.16)
                                              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: driverProv.femalePassengersOnly
                                                ? const Color(0xFFE91E63)
                                                : (isDark ? Colors.white24 : Colors.black12),
                                            width: driverProv.femalePassengersOnly ? 1.3 : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.female_rounded,
                                              size: 14,
                                              color: driverProv.femalePassengersOnly
                                                  ? const Color(0xFFE91E63)
                                                  : (isDark ? Colors.white70 : Colors.black54),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Women Only',
                                              style: TextStyle(
                                                fontSize: layout.fontSize(10),
                                                fontWeight: driverProv.femalePassengersOnly ? FontWeight.w800 : FontWeight.w600,
                                                color: driverProv.femalePassengersOnly
                                                    ? const Color(0xFFE91E63)
                                                    : (isDark ? Colors.white70 : Colors.black87),
                                              ),
                                            ),
                                            if (driverProv.femalePassengersOnly) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                width: 5,
                                                height: 5,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFFE91E63),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Khata Quick Pill
                                    InkWell(
                                      onTap: () => DriverKhataSheet.show(context),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.emeraldGreen.withValues(alpha: 0.13),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.account_balance_wallet_rounded,
                                              color: AppTheme.emeraldGreen,
                                              size: 13,
                                            ),
                                            const SizedBox(width: 4),
                                            ListenableBuilder(
                                              listenable: DriverKhataService(),
                                              builder: (ctx, _) {
                                                final khata = DriverKhataService().todayKhata;
                                                return Text(
                                                  'Khata: PKR ${khata.netCashProfit.toInt()}',
                                                  style: TextStyle(
                                                    color: AppTheme.emeraldGreen,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: layout.fontSize(10),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // AI Advisor Quick Pill
                                    InkWell(
                                      onTap: () async {
                                        final allowed = await AiConsentDialog.ensureConsent(context);
                                        if (!allowed || !context.mounted) return;
                                        Navigator.of(context).pushNamed('/earnings-advisor');
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accentTeal.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: AppTheme.accentTeal.withValues(alpha: 0.35),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.psychology,
                                              size: 13,
                                              color: AppTheme.accentTeal,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'AI Advisor',
                                              style: TextStyle(
                                                fontSize: layout.fontSize(10),
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.accentTeal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (driver.isVerified || driverProv.hasPassedAiVerification)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.verified_user_rounded,
                                              color: AppTheme.emeraldGreen,
                                              size: 13,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Verified Captain',
                                              style: TextStyle(
                                                color: AppTheme.emeraldGreen,
                                                fontSize: layout.fontSize(10),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      InkWell(
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => const DriverVerificationScreen(),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppTheme.accentCyan.withValues(alpha: 0.12)
                                                : AppTheme.primaryBlue.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isDark
                                                  ? AppTheme.accentCyan.withValues(alpha: 0.3)
                                                  : AppTheme.primaryBlue.withValues(alpha: 0.25),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.shield_outlined,
                                                color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                                                size: 13,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Standard • Boost Credibility',
                                                style: TextStyle(
                                                  color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                                                  fontSize: layout.fontSize(10),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                    ),
                  ),
                ),
              ),

              // 2b. En-Route Incoming Pool Request Card
              if (_viewModel.enRoutePoolOffer != null && currentRide != null)
                _buildEnRoutePoolOfferCard(layout, rideProv, isDark),

              // 2c. Live Demand Repositioning Nudge Banner
              if (_viewModel.repositioningNudge != null && currentRide == null)
                _buildRepositioningNudgeBanner(layout, isDark),

              // 3. Bottom Cockpit Card
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: layout.maxCardWidth,
                      maxHeight: layout.screenHeight * (layout.isHeightCompact ? 0.36 : 0.44),
                    ),
                    child: GlassContainer(
                      borderRadius: 24,
                      blur: 24,
                      shadows: isDark ? AppTheme.darkElevation : AppTheme.premiumElevation,
                      padding: EdgeInsets.fromLTRB(
                        layout.horizontalPadding,
                        layout.scale(10),
                        layout.horizontalPadding,
                        layout.scale(8),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: currentRide == null
                            ? _buildWaitingOrEarningsCard(
                                layout,
                                driver,
                                driverProv,
                                rideProv,
                                authProv,
                              )
                            : _buildActiveDriverRideCard(
                                layout,
                                currentRide,
                                rideProv,
                                driverProv,
                                authProv,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: currentRide != null
              ? null
              : Padding(
                  padding: EdgeInsets.only(
                    bottom: layout.isHeightCompact ? 8 : 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'driver_hotspots_btn',
                        tooltip: _viewModel.showHotspots ? 'Hide Demand Hotspots' : 'Show Demand Hotspots',
                        backgroundColor: _viewModel.showHotspots ? AppTheme.amberWarning : AppTheme.primaryNavy,
                        foregroundColor: _viewModel.showHotspots ? Colors.black : Colors.white,
                        child: Icon(_viewModel.showHotspots ? Icons.local_fire_department : Icons.local_fire_department_outlined, size: 20),
                        onPressed: () => setState(() => _viewModel.toggleHotspots()),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'driver_history_btn',
                        tooltip: 'Trip History',
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: AppTheme.accentCyan,
                        child: const Icon(Icons.history_rounded, size: 20),
                        onPressed: () => Navigator.of(context).pushNamed('/history'),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'driver_ai_chat_btn',
                        tooltip: 'AI Assistant',
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: AppTheme.accentCyan,
                        child: const Icon(Icons.auto_awesome, size: 20),
                        onPressed: () async {
                          final allowed = await AiConsentDialog.ensureConsent(
                            context,
                          );
                          if (!allowed || !context.mounted) return;
                          Navigator.of(context).pushNamed('/ai-chat');
                        },
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSosBanner(
    ResponsiveLayoutHelper layout,
    RideProvider rideProv,
    LocationProvider locProv,
  ) {
    final sos = rideProv.activeSos!;
    final age = DateTime.now().difference(sos.createdAt);
    final ageLabel = age.inMinutes < 1
        ? 'just now'
        : '${age.inMinutes} min ago';

    return Semantics(
      liveRegion: true,
      label: 'Emergency alert active. The rider triggered SOS $ageLabel.',
      child: Container(
        padding: EdgeInsets.all(layout.scale(14)),
        decoration: BoxDecoration(
          color: AppTheme.sunsetCoral,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.glowShadow(
            AppTheme.sunsetCoral,
            opacity: 0.5,
            blur: 18,
          ),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
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
                      label: const Text(
                        'Call rider',
                        style: TextStyle(fontSize: 12.5),
                      ),
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
                      label: const Text(
                        'Call 15',
                        style: TextStyle(fontSize: 12.5),
                      ),
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
        backgroundColor: error == null
            ? AppTheme.emeraldGreen
            : AppTheme.sunsetCoral,
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
    final c = AppColors.of(layout.context);
    final isDark = Theme.of(layout.context).brightness == Brightness.dark;
    final requests = driverProv.isOnline
        ? rideProv.availableRides
        : const <RideModel>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(height: layout.scale(12)),

        if (driverProv.isOnline) ...[
          // Auto-Acceptance Settings Card
          Container(
            margin: EdgeInsets.only(bottom: layout.isHeightCompact ? 6 : 8),
            padding: EdgeInsets.symmetric(
              horizontal: layout.scale(10),
              vertical: layout.isHeightCompact ? 6 : layout.scale(8),
            ),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _viewModel.autoAcceptMode != AutoAcceptMode.off
                    ? AppTheme.accentCyan.withValues(alpha: 0.5)
                    : c.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _viewModel.autoAcceptMode == AutoAcceptMode.currentRate
                          ? Icons.flash_on_rounded
                          : (_viewModel.autoAcceptMode == AutoAcceptMode.aiValuation
                              ? Icons.auto_awesome
                              : Icons.touch_app_rounded),
                      size: layout.scale(16),
                      color: _viewModel.autoAcceptMode != AutoAcceptMode.off
                          ? AppTheme.accentCyan
                          : c.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Auto-Accept Incoming Rides',
                        style: TextStyle(
                          color: isDark ? Colors.white : c.textPrimary,
                          fontSize: layout.fontSize(11.5),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_viewModel.autoAcceptMode != AutoAcceptMode.off)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _viewModel.autoAcceptMode == AutoAcceptMode.currentRate
                              ? 'CURRENT RATE'
                              : 'AI VALUE (±5%)',
                          style: TextStyle(
                            fontSize: layout.fontSize(9),
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentCyan,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: layout.isHeightCompact ? 4 : 6),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _viewModel.setAutoAcceptMode(AutoAcceptMode.off),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(vertical: layout.isHeightCompact ? 4.5 : 5.5),
                          decoration: BoxDecoration(
                            color: _viewModel.autoAcceptMode == AutoAcceptMode.off
                                ? AppTheme.slateMuted.withValues(alpha: 0.2)
                                : c.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _viewModel.autoAcceptMode == AutoAcceptMode.off
                                  ? AppTheme.slateMuted
                                  : c.border,
                              width: _viewModel.autoAcceptMode == AutoAcceptMode.off ? 1.5 : 1.0,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Manual',
                              style: TextStyle(
                                fontSize: layout.fontSize(10),
                                fontWeight: _viewModel.autoAcceptMode == AutoAcceptMode.off
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _viewModel.autoAcceptMode == AutoAcceptMode.off
                                    ? (isDark ? Colors.white : AppTheme.primaryNavy)
                                    : c.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: InkWell(
                        onTap: () => _viewModel.setAutoAcceptMode(AutoAcceptMode.currentRate),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(vertical: layout.isHeightCompact ? 4.5 : 5.5),
                          decoration: BoxDecoration(
                            color: _viewModel.autoAcceptMode == AutoAcceptMode.currentRate
                                ? AppTheme.emeraldGreen.withValues(alpha: 0.2)
                                : c.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _viewModel.autoAcceptMode == AutoAcceptMode.currentRate
                                  ? AppTheme.emeraldGreen
                                  : c.border,
                              width: _viewModel.autoAcceptMode == AutoAcceptMode.currentRate ? 1.5 : 1.0,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Current Rate',
                              style: TextStyle(
                                fontSize: layout.fontSize(10),
                                fontWeight: _viewModel.autoAcceptMode == AutoAcceptMode.currentRate
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _viewModel.autoAcceptMode == AutoAcceptMode.currentRate
                                    ? AppTheme.emeraldGreen
                                    : c.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: InkWell(
                        onTap: () => _viewModel.setAutoAcceptMode(AutoAcceptMode.aiValuation),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(vertical: layout.isHeightCompact ? 4.5 : 5.5),
                          decoration: BoxDecoration(
                            color: _viewModel.autoAcceptMode == AutoAcceptMode.aiValuation
                                ? AppTheme.accentCyan.withValues(alpha: 0.2)
                                : c.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _viewModel.autoAcceptMode == AutoAcceptMode.aiValuation
                                  ? AppTheme.accentCyan
                                  : c.border,
                              width: _viewModel.autoAcceptMode == AutoAcceptMode.aiValuation ? 1.5 : 1.0,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'AI Value (±5%)',
                              style: TextStyle(
                                fontSize: layout.fontSize(10),
                                fontWeight: _viewModel.autoAcceptMode == AutoAcceptMode.aiValuation
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _viewModel.autoAcceptMode == AutoAcceptMode.aiValuation
                                    ? AppTheme.accentCyan
                                    : c.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: layout.isHeightCompact ? 4 : 5),
                Text(
                  _viewModel.autoAcceptMode == AutoAcceptMode.currentRate
                      ? 'Instant auto-acceptance at rider\'s offered fare (>= PKR 50).'
                      : (_viewModel.autoAcceptMode == AutoAcceptMode.aiValuation
                          ? 'Auto-accepts bids within ±5% or above AI fair sweet spot.'
                          : 'Manual review: you decide on each incoming bid.'),
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: layout.fontSize(9.5),
                  ),
                ),
              ],
            ),
          ),

          // Trigger automated acceptance if requests arrive while active
          Builder(
            builder: (ctx) {
              if (requests.isNotEmpty && _viewModel.autoAcceptMode != AutoAcceptMode.off) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _viewModel.evaluateIncomingRidesForAutoAccept(
                    requests: requests,
                    rideProv: rideProv,
                    driver: driverProv.driverProfile,
                    driverName: authProv.currentUser.fullName,
                  );
                });
              }
              return const SizedBox.shrink();
            },
          ),

          if (requests.isEmpty)
            Container(
              padding: EdgeInsets.all(layout.scale(12)),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentCyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      label: 'Waiting for ride requests nearby',
                      child: Text(
                        'Waiting for ride requests nearby…',
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: layout.fontSize(12),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final request in requests)
              Builder(
                builder: (context) {
                  final cachedAiFare = _viewModel.getCachedAiValuation(request.id);
                  if (cachedAiFare == null) {
                    _viewModel.getOrCalculateAiValuation(request);
                  }
                  final aiFare = cachedAiFare ?? request.offeredFare;
                  final analysis = _viewModel.analyzeFare(
                    offeredFare: request.offeredFare,
                    aiValuation: aiFare,
                  );

                  // Highlight card border & background if rider's bid is significantly low or fair
                  final cardBorderColor = analysis.isLow
                      ? Colors.amber.withValues(alpha: 0.6)
                      : AppTheme.accentCyan.withValues(alpha: 0.35);
                  final cardBgColor = analysis.isLow
                      ? Colors.amber.withValues(alpha: 0.08)
                      : AppTheme.accentCyan.withValues(alpha: 0.10);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(layout.scale(12)),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cardBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Builder(
                              builder: (_) {
                                final vType = VehicleTypeX.fromString(request.vehicleType);
                                return Icon(
                                  vType.icon,
                                  color: analysis.isLow ? Colors.amber : AppTheme.accentCyan,
                                  size: 16,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                label:
                                    'New ${VehicleTypeX.fromString(request.vehicleType).title} request for ${CurrencyFormatter.format(request.offeredFare)}',
                                child: Text(
                                  '${VehicleTypeX.fromString(request.vehicleType).title} • ${CurrencyFormatter.format(request.offeredFare)}',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: layout.fontSize(13),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (request.riderGender?.toLowerCase() == 'female')
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE91E63).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFFE91E63).withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.female_rounded,
                                          size: 11,
                                          color: Color(0xFFE91E63),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Female Rider • Verified',
                                          style: TextStyle(
                                            fontSize: layout.fontSize(9.5),
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFE91E63),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    VehicleTypeX.fromString(request.vehicleType).name.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: layout.fontSize(9.5),
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ),
                                ),
                                if (VehicleTypeX.fromString(request.vehicleType) == VehicleType.car)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.people_alt_rounded, size: 10, color: AppTheme.emeraldGreen),
                                        const SizedBox(width: 3),
                                        Text(
                                          request.bookedSeats > 1
                                              ? '${request.bookedSeats} Seats'
                                              : '1 Seat',
                                          style: TextStyle(
                                            fontSize: layout.fontSize(9.5),
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.emeraldGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request.pickup.address.isEmpty
                              ? '${request.distanceKm.toStringAsFixed(1)} km trip'
                              : request.pickup.address,
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: layout.fontSize(11),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // AI Market Valuation guidance tag
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: analysis.isLow
                                ? Colors.amber.withValues(alpha: 0.15)
                                : AppTheme.emeraldGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: analysis.isLow
                                  ? Colors.amber.withValues(alpha: 0.4)
                                  : AppTheme.emeraldGreen.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                analysis.isLow ? Icons.warning_amber_rounded : Icons.auto_awesome,
                                size: 13,
                                color: analysis.isLow ? Colors.amber.shade700 : AppTheme.emeraldGreen,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  analysis.tagMessage,
                                  style: TextStyle(
                                    fontSize: layout.fontSize(10.5),
                                    fontWeight: FontWeight.w700,
                                    color: analysis.isLow
                                        ? (isDark ? Colors.amber.shade300 : Colors.amber.shade900)
                                        : (isDark ? AppTheme.emeraldGreen : Colors.green.shade800),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Live Trip Economics Preview & Downward Competitive Bidding
                        Builder(
                          builder: (ctx) {
                            final vType = VehicleTypeX.fromString(request.vehicleType);
                            final driverCarModel = driver.vehicle.model;
                            final carEngineTier = vType == VehicleType.car
                                ? CarEngineTierX.fromCarModel(driverCarModel)
                                : null;
                            final isCar = vType == VehicleType.car;
                            final econ = TripEconomics.calculate(
                              vehicleType: vType,
                              distanceKm: request.distanceKm,
                              durationMin: request.durationMin,
                              fare: request.offeredFare,
                              bookedSeats: request.bookedSeats,
                              isAiPredicted: true,
                              carModel: driverCarModel,
                              carEngineTier: carEngineTier,
                              acEnabled: isCar,
                            );
                            final costFloor = econ.costFloor;
                            final fare20 = request.offeredFare - 20.0;
                            final fare50 = request.offeredFare - 50.0;
                            final canBid20 = fare20 >= costFloor && fare20 >= 50.0;
                            final canBid50 = fare50 >= costFloor && fare50 >= 50.0;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => TripEconomicsSheet.show(
                                    context,
                                    economics: econ,
                                    isDriverView: true,
                                    carEngineTier: carEngineTier,
                                    acEnabled: isCar,
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF161F30) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppTheme.emeraldGreen.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.local_gas_station_rounded, size: 13, color: Colors.orange),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Fuel: ${CurrencyFormatter.format(econ.fuelCost)}',
                                          style: TextStyle(
                                            fontSize: layout.fontSize(10),
                                            color: c.textMuted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.account_balance_wallet_rounded, size: 13, color: AppTheme.emeraldGreen),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Net Profit: ${CurrencyFormatter.format(econ.driverNetProfit)}',
                                            style: TextStyle(
                                              fontSize: layout.fontSize(10),
                                              color: AppTheme.emeraldGreen,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          'Details >',
                                          style: TextStyle(
                                            fontSize: layout.fontSize(9.5),
                                            color: AppTheme.accentCyan,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(top: 6, bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentCyan.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.bolt_rounded, size: 13, color: AppTheme.accentCyan),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Bid at or below PKR ${request.offeredFare.toInt()} to win instantly',
                                          style: TextStyle(
                                            fontSize: layout.fontSize(10.5),
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? AppTheme.accentCyan : AppTheme.primaryNavy,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: SizedBox(
                                        height: layout.touchTarget(44),
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.emeraldGreen,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                          ),
                                          onPressed: () => _viewModel.submitCounterOffer(
                                            rideProv: rideProv,
                                            driver: driver,
                                            driverName: authProv.currentUser.fullName,
                                            rideId: request.id,
                                            fare: request.offeredFare,
                                          ),
                                          child: Text(
                                            'Accept PKR ${request.offeredFare.toInt()}',
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      height: layout.touchTarget(44),
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: canBid20 ? AppTheme.accentCyan : c.textMuted,
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          minimumSize: Size.zero,
                                        ),
                                        onPressed: canBid20
                                            ? () => _viewModel.submitCounterOffer(
                                                  rideProv: rideProv,
                                                  driver: driver,
                                                  driverName: authProv.currentUser.fullName,
                                                  rideId: request.id,
                                                  fare: fare20,
                                                )
                                            : null,
                                        child: Text(
                                          '-Rs 20',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: canBid20 ? null : c.textMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      height: layout.touchTarget(44),
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: canBid50 ? Colors.orange.shade400 : c.textMuted,
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          minimumSize: Size.zero,
                                        ),
                                        onPressed: canBid50
                                            ? () => _viewModel.submitCounterOffer(
                                                  rideProv: rideProv,
                                                  driver: driver,
                                                  driverName: authProv.currentUser.fullName,
                                                  rideId: request.id,
                                                  fare: fare50,
                                                )
                                            : null,
                                        child: Text(
                                          '-Rs 50',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: canBid50 ? null : c.textMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      height: layout.touchTarget(44),
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.accentCyan,
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          minimumSize: Size.zero,
                                        ),
                                        onPressed: () => _showDriverCustomFareSheet(
                                          context: context,
                                          rideProv: rideProv,
                                          driver: driver,
                                          driverName: authProv.currentUser.fullName,
                                          rideId: request.id,
                                          initialFare: request.offeredFare,
                                          costFloor: costFloor,
                                        ),
                                        child: const Icon(Icons.edit_note_rounded, size: 20),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
          SizedBox(height: layout.scale(12)),
        ],

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Driver Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: layout.fontSize(16),
                ),
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
                'Fixed 2% Fee (Always)',
                style: TextStyle(
                  color: AppTheme.emeraldGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: layout.fontSize(11),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: layout.scale(12)),

        // Quick Stats Row
        Row(
          children: [
            _buildStatBox(
              layout,
              'Total Rides',
              '${driver.totalRides}',
              Icons.check_circle_outline,
              0,
            ),
            const SizedBox(width: 8),
            _buildStatBox(
              layout,
              'Rating',
              '★ ${driver.rating}',
              Icons.star_border,
              1,
            ),
            const SizedBox(width: 8),
            _buildStatBox(
              layout,
              'Saved Fees',
              CurrencyFormatter.format(driver.totalEarnings * 0.13),
              Icons.savings_outlined,
              2,
            ),
          ],
        ),
        SizedBox(height: layout.scale(14)),

        // Withdraw earnings
        SizedBox(
          height: layout.touchTarget(48),
          child: ElevatedButton.icon(
            icon: const Icon(
              Icons.account_balance_wallet,
              color: AppTheme.primaryNavy,
            ),
            label: Text(
              'Withdraw Earnings (${CurrencyFormatter.format(driverProv.availablePayoutBalance)})',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: AppTheme.primaryNavy,
            ),
            onPressed:
                _viewModel.isProcessingPayout ||
                    driverProv.availablePayoutBalance <= 0
                ? null
                : () => _showPayoutSheet(
                    driver,
                    driverProv.availablePayoutBalance,
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPayoutSheet(
    DriverProfile driver,
    double availableBalance,
  ) async {
    const rails = <({String id, String label, String hint})>[
      (
        id: 'jazzcash',
        label: 'JazzCash wallet',
        hint: 'Mobile number, e.g. 03001234567',
      ),
      (
        id: 'easypaisa',
        label: 'Easypaisa wallet',
        hint: 'Mobile number, e.g. 03451234567',
      ),
      (
        id: 'raast',
        label: 'Raast / bank transfer',
        hint: 'IBAN, e.g. PK36SCBL0000001123456702',
      ),
      (
        id: 'manual',
        label: 'Manual settlement',
        hint: 'Account note for our team',
      ),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: c.textPrimary,
                  ),
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
                      color: selectedRail == rail.id
                          ? AppTheme.primaryBlue
                          : c.textMuted,
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
                    hintText: rails
                        .firstWhere((r) => r.id == selectedRail)
                        .hint,
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
        backgroundColor: result.accepted
            ? AppTheme.emeraldGreen
            : AppTheme.sunsetCoral,
        duration: Duration(seconds: result.accepted ? 4 : 8),
      ),
    );
  }

  Widget _buildStatBox(
    ResponsiveLayoutHelper layout,
    String label,
    String value,
    IconData icon,
    int index,
  ) {
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
              Text(
                value,
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: layout.fontSize(14),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: layout.fontSize(10),
                ),
              ),
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
    final c = AppColors.of(layout.context);
    final isDark = Theme.of(layout.context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(height: layout.scale(10)),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Semantics(
                      liveRegion: true,
                      label: 'Trip status: ${ride.status.displayName}',
                      child: Text(
                        ride.status.displayName,
                        style: TextStyle(
                          color: AppTheme.accentCyan,
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(11.5),
                        ),
                      ),
                    ),
                  ),
                  if (VehicleTypeX.fromString(ride.vehicleType) == VehicleType.car) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_alt_rounded, size: 11, color: AppTheme.emeraldGreen),
                          const SizedBox(width: 4),
                          Text(
                            ride.bookedSeats > 1
                                ? '${ride.bookedSeats} Seats'
                                : '1 Seat',
                            style: TextStyle(
                              color: AppTheme.emeraldGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: layout.fontSize(10.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ride.emptySeats > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.airline_seat_recline_extra_rounded, size: 11, color: AppTheme.accentCyan),
                            const SizedBox(width: 4),
                            Text(
                              '${ride.emptySeats} Empty',
                              style: TextStyle(
                                color: AppTheme.accentCyan,
                                fontWeight: FontWeight.w700,
                                fontSize: layout.fontSize(10.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Fare: ${CurrencyFormatter.format(ride.acceptedFare ?? ride.offeredFare)}',
              style: TextStyle(
                color: AppTheme.emeraldGreen,
                fontWeight: FontWeight.w800,
                fontSize: layout.fontSize(14),
              ),
            ),
          ],
        ),
        SizedBox(height: layout.scale(10)),

        Text(
          'Pickup: ${ride.pickup.address}',
          style: TextStyle(
            color: isDark ? Colors.white : c.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: layout.fontSize(13),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          'Dropoff: ${ride.dropoff.address}',
          style: TextStyle(
            color: c.textMuted,
            fontSize: layout.fontSize(12),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (ride.waypoints.isNotEmpty) ...[
          _buildMultiStopWaypointsSection(layout, ride, rideProv, authProv, driverProv, isDark, c),
        ],
        // Active Trip Economics (Fuel, Maintenance, Profit)
        Builder(
          builder: (ctx) {
            final vType = VehicleTypeX.fromString(ride.vehicleType);
            final driverCarModel = driverProv.driver.vehicle.model;
            final carEngineTier = vType == VehicleType.car
                ? CarEngineTierX.fromCarModel(driverCarModel)
                : null;
            final isCar = vType == VehicleType.car;
            final econ = TripEconomics.calculate(
              vehicleType: vType,
              distanceKm: ride.distanceKm,
              durationMin: ride.durationMin,
              fare: ride.acceptedFare ?? ride.offeredFare,
              bookedSeats: ride.bookedSeats,
              isAiPredicted: true,
              carModel: driverCarModel,
              carEngineTier: carEngineTier,
              acEnabled: isCar,
            );
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => TripEconomicsSheet.show(
                context,
                economics: econ,
                isDriverView: true,
                carEngineTier: carEngineTier,
                acEnabled: isCar,
              ),
              child: Container(
                margin: EdgeInsets.only(top: layout.scale(8)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161F30) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_gas_station_rounded, size: 15, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'Fuel: ${CurrencyFormatter.format(econ.fuelCost)}',
                      style: TextStyle(
                        fontSize: layout.fontSize(11),
                        color: c.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.account_balance_wallet_rounded, size: 15, color: AppTheme.emeraldGreen),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Take-Home: ${CurrencyFormatter.format(econ.driverNetProfit)}',
                        style: TextStyle(
                          fontSize: layout.fontSize(11),
                          color: AppTheme.emeraldGreen,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Economics >',
                        style: TextStyle(
                          fontSize: layout.fontSize(10),
                          color: AppTheme.accentCyan,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // En-Route Co-Riders (Carpool Corridor with Empty Seats - Cars Only)
        if (VehicleTypeX.fromString(ride.vehicleType) == VehicleType.car && ride.emptySeats > 0)
          Builder(
            builder: (ctx) {
              final cachedPlan = _viewModel.getCachedRoutePlan(ride.id);
              final points = cachedPlan?.routes.firstOrNull?.polylinePoints ?? const <LatLng>[];
              final enRouteMatches = RouteCorridorService.findEnRouteMatches(
                activeRide: ride,
                activeRoutePoints: points,
                candidateRides: rideProv.availableRides,
              );

              return Container(
                margin: EdgeInsets.only(top: layout.scale(8)),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF132035) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.accentCyan.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.alt_route_rounded,
                          size: 16,
                          color: AppTheme.accentCyan,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Co-Riders Along Your Route',
                          style: TextStyle(
                            fontSize: layout.fontSize(11.5),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentCyan,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${ride.emptySeats} Seats Available',
                            style: TextStyle(
                              fontSize: layout.fontSize(10),
                              fontWeight: FontWeight.w700,
                              color: AppTheme.emeraldGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enRouteMatches.isNotEmpty
                          ? '${enRouteMatches.length} passenger${enRouteMatches.length > 1 ? 's' : ''} along your route! Pick them up with virtually zero extra petrol.'
                          : 'Carrying empty seats? The cockpit will instantly notify you when passengers request a ride along your active path.',
                      style: TextStyle(
                        fontSize: layout.fontSize(10),
                        color: c.textMuted,
                      ),
                    ),
                    if (enRouteMatches.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...enRouteMatches.map((match) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: c.border.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Pickup: ${match.ride.pickup.address}',
                                      style: TextStyle(
                                        fontSize: layout.fontSize(11),
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : c.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    CurrencyFormatter.format(match.ride.offeredFare),
                                    style: TextStyle(
                                      fontSize: layout.fontSize(12),
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.emeraldGreen,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Dropoff: ${match.ride.dropoff.address}',
                                style: TextStyle(
                                  fontSize: layout.fontSize(10),
                                  color: c.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+${match.detourKm.toStringAsFixed(1)} km detour (~PKR ${match.extraPetrolCost.toInt()} fuel)',
                                      style: TextStyle(
                                        fontSize: layout.fontSize(9.5),
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '+PKR ${match.netProfitBoost.toInt()} Net',
                                      style: TextStyle(
                                        fontSize: layout.fontSize(9.5),
                                        color: AppTheme.emeraldGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  SizedBox(
                                    height: 28,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.emeraldGreen,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                      onPressed: () {
                                        _viewModel.submitCounterOffer(
                                          rideProv: rideProv,
                                          driver: driverProv.driverProfile,
                                          driverName: authProv.currentUser.fullName,
                                          rideId: match.ride.id,
                                          fare: match.ride.offeredFare,
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Sent offer to co-rider at PKR ${match.ride.offeredFare.toInt()}.'),
                                            backgroundColor: AppTheme.emeraldGreen,
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'Pick Up Along Way',
                                        style: TextStyle(
                                          fontSize: layout.fontSize(10),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              );
            },
          ),
        SizedBox(height: layout.scale(8)),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              var plan = _viewModel.getCachedRoutePlan(ride.id);
              plan ??= await _viewModel.getOrFetchRoute(ride);
              final routeOption = plan?.routes.firstOrNull ??
                  RouteOption(
                    id: 'ride_${ride.id}',
                    polylinePoints: [
                      LatLng(ride.pickup.latitude, ride.pickup.longitude),
                      LatLng(ride.dropoff.latitude, ride.dropoff.longitude),
                    ],
                    distanceKm: ride.distanceKm,
                    durationMin: (ride.distanceKm * 2.0).clamp(5.0, 999.0),
                    staticDurationMin:
                        (ride.distanceKm * 2.0).clamp(5.0, 999.0),
                    summary: '${ride.pickup.address} to ${ride.dropoff.address}',
                    labels: const ['FASTEST'],
                    trafficLevel: 'NORMAL',
                    trafficIntervals: const [],
                    steps: const [],
                    economics: const RouteEconomics(
                      fuelCost: 0,
                      maintenanceCost: 0,
                      tollCost: 0,
                      driverCost: 0,
                      riderFare: 0,
                      commission: 0,
                      driverProfit: 0,
                      profitPerMin: 0,
                    ),
                  );

              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoutePreviewScreen(
                    explicitPickup: ride.pickup,
                    explicitDropoff: ride.dropoff,
                    explicitRoutes: [routeOption],
                  ),
                ),
              );
            },
            icon: const Icon(
              Icons.directions,
              size: 16,
              color: AppTheme.accentCyan,
            ),
            label: const Text(
              'Turn-by-Turn Directions',
              style: TextStyle(
                color: AppTheme.accentCyan,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(
                color: AppTheme.accentCyan,
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
            ),
          ),
        ),
        SizedBox(height: layout.scale(10)),

        if (ride.status == RideStatus.requested) ...[
          Builder(
            builder: (context) {
              final cachedAiFare = _viewModel.getCachedAiValuation(ride.id);
              if (cachedAiFare == null) {
                _viewModel.getOrCalculateAiValuation(ride);
              }
              final aiFare = cachedAiFare ?? ride.offeredFare;
              final analysis = _viewModel.analyzeFare(
                offeredFare: ride.offeredFare,
                aiValuation: aiFare,
              );

              final vType = VehicleTypeX.fromString(ride.vehicleType);
              final driverCarModel = driverProv.driverProfile.vehicle.model;
              final carEngineTier = vType == VehicleType.car
                  ? CarEngineTierX.fromCarModel(driverCarModel)
                  : null;
              final isCar = vType == VehicleType.car;
              final econ = TripEconomics.calculate(
                vehicleType: vType,
                distanceKm: ride.distanceKm,
                durationMin: ride.durationMin,
                fare: ride.offeredFare,
                bookedSeats: ride.bookedSeats,
                isAiPredicted: true,
                carModel: driverCarModel,
                carEngineTier: carEngineTier,
                acEnabled: isCar,
              );
              final costFloor = econ.costFloor;
              final fare20 = ride.offeredFare - 20.0;
              final fare50 = ride.offeredFare - 50.0;
              final canBid20 = fare20 >= costFloor && fare20 >= 50.0;
              final canBid50 = fare50 >= costFloor && fare50 >= 50.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: analysis.isLow
                          ? Colors.amber.withValues(alpha: 0.15)
                          : AppTheme.emeraldGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: analysis.isLow
                            ? Colors.amber.withValues(alpha: 0.4)
                            : AppTheme.emeraldGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          analysis.isLow ? Icons.warning_amber_rounded : Icons.auto_awesome,
                          size: 13,
                          color: analysis.isLow ? Colors.amber.shade700 : AppTheme.emeraldGreen,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            analysis.tagMessage,
                            style: TextStyle(
                              fontSize: layout.fontSize(10.5),
                              fontWeight: FontWeight.w700,
                              color: analysis.isLow
                                  ? (isDark ? Colors.amber.shade300 : Colors.amber.shade900)
                                  : (isDark ? AppTheme.emeraldGreen : Colors.green.shade800),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt_rounded, size: 13, color: AppTheme.accentCyan),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Bid at or below PKR ${ride.offeredFare.toInt()} to win instantly',
                            style: TextStyle(
                              fontSize: layout.fontSize(10.5),
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppTheme.accentCyan : AppTheme.primaryNavy,
                            ),
                          ),
                        ),
                        Text(
                          'Est. Profit: PKR ${econ.driverNetProfit.toInt()}',
                          style: TextStyle(
                            fontSize: layout.fontSize(10),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.emeraldGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      // Accept / Match passenger fare to win instantly
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: layout.touchTarget(48),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.emeraldGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            onPressed: () => _viewModel.submitCounterOffer(
                              rideProv: rideProv,
                              driver: driverProv.driverProfile,
                              driverName: authProv.currentUser.fullName,
                              rideId: ride.id,
                              fare: ride.offeredFare,
                            ),
                            child: Text(
                              'Accept PKR ${ride.offeredFare.toInt()}',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Competitive undercut -20 (disabled if below cost floor)
                      SizedBox(
                        height: layout.touchTarget(48),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: canBid20 ? AppTheme.accentCyan : c.textMuted,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                          ),
                          onPressed: canBid20
                              ? () => _viewModel.submitCounterOffer(
                                    rideProv: rideProv,
                                    driver: driverProv.driverProfile,
                                    driverName: authProv.currentUser.fullName,
                                    rideId: ride.id,
                                    fare: fare20,
                                  )
                              : null,
                          child: Text(
                            '-Rs 20',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: canBid20 ? null : c.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Competitive undercut -50 (disabled if below cost floor)
                      SizedBox(
                        height: layout.touchTarget(48),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: canBid50 ? Colors.orange.shade400 : c.textMuted,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                          ),
                          onPressed: canBid50
                              ? () => _viewModel.submitCounterOffer(
                                    rideProv: rideProv,
                                    driver: driverProv.driverProfile,
                                    driverName: authProv.currentUser.fullName,
                                    rideId: ride.id,
                                    fare: fare50,
                                  )
                              : null,
                          child: Text(
                            '-Rs 50',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: canBid50 ? null : c.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Custom Bid
                      SizedBox(
                        height: layout.touchTarget(48),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentCyan,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () => _showDriverCustomFareSheet(
                            context: context,
                            rideProv: rideProv,
                            driver: driverProv.driverProfile,
                            driverName: authProv.currentUser.fullName,
                            rideId: ride.id,
                            initialFare: ride.offeredFare,
                            costFloor: costFloor,
                          ),
                          child: const Icon(Icons.edit_note_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ] else if (ride.status == RideStatus.accepted) ...[
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: layout.touchTarget(48),
                  child: ElevatedButton.icon(
                    icon: const Icon(
                      Icons.near_me,
                      color: AppTheme.primaryNavy,
                    ),
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
                    backgroundColor: AppTheme.accentCyan.withValues(
                      alpha: 0.15,
                    ),
                    foregroundColor: AppTheme.accentCyan,
                  ),
                  icon: const Icon(Icons.phone),
                  tooltip: _riderPhone == null
                      ? 'Rider phone unavailable'
                      : 'Call Rider',
                  onPressed: _riderPhone == null
                      ? null
                      : () => _viewModel.callRider(_riderPhone!),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: layout.touchTarget(48),
                width: layout.touchTarget(48),
                child: StreamBuilder<int>(
                  stream: RideChatService().streamUnreadCount(
                    rideId: ride.id,
                    currentUserId: authProv.currentUser.id,
                  ),
                  builder: (context, snap) {
                    final unread = snap.data ?? 0;
                    return Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      backgroundColor: AppTheme.sunsetCoral,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue.withValues(
                            alpha: 0.15,
                          ),
                          foregroundColor: AppTheme.primaryBlue,
                        ),
                        icon: const Icon(Icons.chat_bubble_rounded),
                        tooltip: 'Chat with Rider',
                        onPressed: () {
                          RideChatSheet.show(
                            context,
                            rideId: ride.id,
                            currentUserId: authProv.currentUser.id,
                            currentUserRole: 'driver',
                            otherUserName: 'Rider',
                            otherUserId: ride.riderId,
                          );
                        },
                      ),
                    );
                  },
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
          GlassContainer(
            isDark: true,
            borderRadius: 16,
            blur: 16,
            padding: const EdgeInsets.all(12),
            shadows: AppTheme.glowShadow(
              AppTheme.accentCyan,
              opacity: 0.15,
              blur: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin, color: AppTheme.accentCyan, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Ask Rider for 4-Digit Verification PIN:',
                      style: TextStyle(
                        color: isDark ? Colors.white : c.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: layout.fontSize(12),
                      ),
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
                          style: TextStyle(
                            color: isDark ? Colors.white : c.textPrimary,
                            fontSize: layout.fontSize(18),
                            letterSpacing: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'PIN',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white30 : c.textMuted.withValues(alpha: 0.5),
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: layout.touchTarget(48),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emeraldGreen,
                        ),
                        onPressed: () async {
                          final success = await _viewModel
                              .verifyPinAndStartTrip(rideProv);
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _viewModel.pinErrorMessage ??
                                      'Invalid verification PIN.',
                                ),
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
          SizedBox(
            height: layout.touchTarget(48),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.flag, color: AppTheme.primaryNavy),
              label: const Text('Complete Trip & Settle Fare'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.emeraldGreen,
              ),
              onPressed: () async {
                final fare = ride.acceptedFare ?? ride.offeredFare;
                final vType = VehicleTypeX.fromString(ride.vehicleType);
                final driverCarModel = driverProv.driver.vehicle.model;
                final carEngineTier = vType == VehicleType.car
                    ? CarEngineTierX.fromCarModel(driverCarModel)
                    : null;
                final tripEconomics = TripEconomics.calculate(
                  distanceKm: ride.distanceKm,
                  durationMin: ride.durationMin,
                  fare: fare,
                  vehicleType: vType,
                  carModel: driverCarModel,
                  carEngineTier: carEngineTier,
                  acEnabled: vType == VehicleType.car,
                );

                final changeResult = await ExactChangeDialog.show(
                  context,
                  fare: fare,
                  tripEconomics: tripEconomics,
                  onConfirm: (res) async {
                    await _viewModel.completeActiveTrip(
                      rideProv: rideProv,
                      driverProv: driverProv,
                      authProv: authProv,
                    );
                    await _viewModel.confirmCashPayment(
                      rideProv: rideProv,
                      rideId: ride.id,
                    );
                  },
                );

                if (!mounted || changeResult == null) return;
                AdService.instance.showPostRideInterstitial();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      changeResult.isTipped
                          ? 'Trip completed! PKR ${changeResult.cashReceived.toInt()} committed to Khata (includes tip).'
                          : 'Trip completed! PKR ${fare.toInt()} committed to Khata.',
                    ),
                    backgroundColor: AppTheme.emeraldGreen,
                  ),
                );
              },
            ),
          ),
        ] else if (ride.status == RideStatus.completed &&
            ride.paymentStatus != 'paid') ...[
          Container(
            padding: EdgeInsets.all(layout.scale(12)),
            decoration: BoxDecoration(
              color: AppTheme.amberWarning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.amberWarning.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      color: AppTheme.amberWarning,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Collect ${CurrencyFormatter.format(ride.acceptedFare ?? ride.offeredFare)} in cash',
                        style: TextStyle(
                          color: isDark ? Colors.white : c.textPrimary,
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emeraldGreen,
                    ),
                    onPressed: _viewModel.isConfirmingCash
                        ? null
                        : () async {
                            final fare = ride.acceptedFare ?? ride.offeredFare;
                            final vType = VehicleTypeX.fromString(ride.vehicleType);
                            final driverCarModel = driverProv.driver.vehicle.model;
                            final carEngineTier = vType == VehicleType.car
                                ? CarEngineTierX.fromCarModel(driverCarModel)
                                : null;
                            final tripEconomics = TripEconomics.calculate(
                              distanceKm: ride.distanceKm,
                              durationMin: ride.durationMin,
                              fare: fare,
                              vehicleType: vType,
                              carModel: driverCarModel,
                              carEngineTier: carEngineTier,
                              acEnabled: vType == VehicleType.car,
                            );

                            final changeResult = await ExactChangeDialog.show(
                              context,
                              fare: fare,
                              tripEconomics: tripEconomics,
                              onConfirm: (res) async {
                                final error = await _viewModel.confirmCashPayment(
                                  rideProv: rideProv,
                                  rideId: ride.id,
                                );
                                if (error == null) {
                                  await driverProv.loadForUser(
                                    authProv.currentUser.id,
                                  );
                                }
                              },
                            );

                            if (!mounted || changeResult == null) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  changeResult.isTipped
                                      ? 'Cash payment & tip recorded: PKR ${changeResult.cashReceived.toInt()} committed to Khata.'
                                      : 'Cash payment recorded. PKR ${fare.toInt()} committed to Khata.',
                                ),
                                backgroundColor: AppTheme.emeraldGreen,
                              ),
                            );
                          },
                    child: _viewModel.isConfirmingCash
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Confirm cash received (Calculate Change)'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool _shouldShowCredibilityCard(DriverProfile driver, DriverProvider driverProv) {
    if (_isCredibilityCardDismissed) return false;
    final isVerified = driver.isVerified || driverProv.hasPassedAiVerification;
    return !isVerified;
  }

  Widget _buildCredibilityCard({
    required ResponsiveLayoutHelper layout,
    required AppColors c,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.accentTeal.withValues(alpha: 0.12)
            : AppTheme.emeraldGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.emeraldGreen.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppTheme.emeraldGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DriverVerificationScreen(),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Boost Your Credibility',
                        style: TextStyle(
                          fontSize: layout.fontSize(13.5),
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Optional',
                          style: TextStyle(
                            fontSize: layout.fontSize(9.5),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.emeraldGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Verify your CNIC & license to earn a Verified Badge and win more rides (Optional)',
                    style: TextStyle(
                      fontSize: layout.fontSize(11.5),
                      color: c.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: c.textMuted,
            ),
            tooltip: 'Dismiss',
            onPressed: () {
              setState(() {
                _isCredibilityCardDismissed = true;
              });
            },
          ),
        ],
      ),
    );
  }

  bool _shouldShowWomenDriverPromo(DriverProfile driver) {
    if (_isWomenDriverPromoDismissed) return false;
    final isFemale = driver.gender?.toLowerCase() == 'female';
    final isUnverified = !driver.isVerified || !driver.isGenderVerified;
    return isFemale || isUnverified || driver.gender == null;
  }

  Widget _buildWomenDriverPromoBanner({
    required ResponsiveLayoutHelper layout,
    required DriverProfile driver,
    required DriverProvider driverProv,
    required bool isDark,
  }) {
    final isVerified = driver.isVerified || driverProv.hasPassedAiVerification;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFF4A148C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF880E4F).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(layout.scale(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEW: Women Passengers Only Mode',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: layout.fontSize(12.5),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Drive with complete peace of mind—accept rides exclusively from verified female passengers and keep 98% of every fare.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: layout.fontSize(10.5),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() => _isWomenDriverPromoDismissed = true);
                      NativeStorageService().setBool('promo_dismissed_women_driver_mode_v1', true);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.close, color: Colors.white70, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      if (driver.gender?.toLowerCase() == 'female' && isVerified && driver.isGenderVerified) {
                        await _viewModel.toggleFemalePassengersOnly(driverProv: driverProv, enabled: true);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Women Passengers Only mode activated!'),
                              backgroundColor: Color(0xFFE91E63),
                            ),
                          );
                        }
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DriverVerificationScreen()),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF880E4F),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      (driver.gender?.toLowerCase() == 'female' && isVerified && driver.isGenderVerified)
                          ? 'Enable Women-Only Mode'
                          : 'Verify CNIC to Unlock',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: layout.fontSize(11),
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

  void _showWomenOnlyDriverGatingDialog(BuildContext context, String message, DriverProfile driver) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.female_rounded, color: Color(0xFFE91E63), size: 24),
            SizedBox(width: 8),
            Text('Women-Only Mode'),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DriverVerificationScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE91E63),
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify CNIC / Documents'),
          ),
        ],
      ),
    );
  }

  Set<Circle> _buildDemandCircles() {
    if (!_viewModel.showHotspots) return const {};
    return _viewModel.demandHotspots.map((h) {
      final isHigh = h.isHighDemand;
      final color = isHigh ? AppTheme.sunsetCoral : AppTheme.amberWarning;
      return Circle(
        circleId: CircleId('hotspot_${h.cellId}'),
        center: LatLng(h.lat, h.lng),
        radius: h.radiusM,
        fillColor: color.withValues(alpha: isHigh ? 0.28 : 0.20),
        strokeColor: color.withValues(alpha: isHigh ? 0.85 : 0.70),
        strokeWidth: 2,
      );
    }).toSet();
  }

  Widget _buildRepositioningNudgeBanner(ResponsiveLayoutHelper layout, bool isDark) {
    final nudge = _viewModel.repositioningNudge;
    final hotspot = _viewModel.targetHotspot;
    if (nudge == null || hotspot == null) return const SizedBox.shrink();

    return Positioned(
      top: 75,
      left: layout.horizontalPadding,
      right: layout.horizontalPadding,
      child: GlassContainer(
        borderRadius: 16,
        blur: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shadows: AppTheme.glowShadow(AppTheme.amberWarning, opacity: 0.35, blur: 14),
        borderColor: AppTheme.amberWarning.withValues(alpha: 0.6),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: AppTheme.amberWarning, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HOTSPOT NUDGE',
                    style: TextStyle(
                      fontSize: layout.fontSize(10),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppTheme.amberWarning,
                    ),
                  ),
                  Text(
                    nudge,
                    style: TextStyle(
                      fontSize: layout.fontSize(11.5),
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amberWarning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
              onPressed: () {
                _viewModel.navigateExternally(hotspot.lat, hotspot.lng);
              },
              child: const Text('Go', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: Colors.white70,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _viewModel.dismissRepositioningNudge()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnRoutePoolOfferCard(ResponsiveLayoutHelper layout, RideProvider rideProv, bool isDark) {
    final offer = _viewModel.enRoutePoolOffer;
    if (offer == null) return const SizedBox.shrink();

    final extraPkr = offer['extraEarningsPkr'] ?? offer['fare'] ?? '350';
    final detourKm = offer['detourKm'] ?? '1.2';
    final pickup = offer['pickupAddress'] ?? 'Nearby stop';
    final dropoff = offer['dropoffAddress'] ?? 'Along route';
    final rideId = offer['rideId']?.toString() ?? '';
    final parentRideId = offer['parentRideId']?.toString() ?? rideProv.currentRide?.id ?? '';

    return Positioned(
      bottom: 280,
      left: layout.horizontalPadding,
      right: layout.horizontalPadding,
      child: PulsingGlowWidget(
        glowColor: AppTheme.accentCyan,
        child: GlassContainer(
          borderRadius: 20,
          blur: 24,
          padding: const EdgeInsets.all(14),
          borderColor: AppTheme.accentCyan,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.alt_route_rounded, color: AppTheme.accentCyan, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En-Route +PKR $extraPkr • +$detourKm km detour',
                      style: TextStyle(
                        color: AppTheme.accentCyan,
                        fontWeight: FontWeight.w800,
                        fontSize: layout.fontSize(13.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Pickup: $pickup\nDropoff: $dropoff',
                style: TextStyle(
                  fontSize: layout.fontSize(11.5),
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _viewModel.clearEnRoutePoolOffer()),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emeraldGreen),
                      onPressed: _viewModel.isAcceptingPoolOffer
                          ? null
                          : () async {
                              await _viewModel.acceptEnRoutePoolOffer(
                                rideProv: rideProv,
                                rideId: rideId,
                                parentRideId: parentRideId,
                              );
                              setState(() {});
                            },
                      child: Text(_viewModel.isAcceptingPoolOffer ? 'Accepting...' : 'Accept Co-Rider'),
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

  Widget _buildMultiStopWaypointsSection(
    ResponsiveLayoutHelper layout,
    RideModel ride,
    RideProvider rideProv,
    AuthProvider authProv,
    DriverProvider driverProv,
    bool isDark,
    dynamic c,
  ) {
    final waypoints = ride.waypoints;
    final activeIndex = _viewModel.getActiveWaypointIndex(ride);
    final activeWaypoint = _viewModel.getActiveWaypoint(ride);

    return Container(
      margin: EdgeInsets.only(top: layout.scale(8), bottom: layout.scale(4)),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132238) : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.linear_scale_rounded, size: 16, color: AppTheme.accentCyan),
              const SizedBox(width: 6),
              Text(
                'Multi-Stop Route (${waypoints.where((w) => w['completed'] == true).length}/${waypoints.length} Done)',
                style: TextStyle(
                  fontSize: layout.fontSize(12),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...waypoints.asMap().entries.map((entry) {
            final idx = entry.key;
            final w = entry.value;
            final isCompleted = w['completed'] == true;
            final isCurrent = idx == activeIndex;
            final isPickup = w['type'] == 'pickup';

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppTheme.accentCyan.withValues(alpha: 0.15)
                    : (isCompleted ? Colors.white10 : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCurrent ? AppTheme.accentCyan : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : (isPickup ? Icons.person_pin_circle_rounded : Icons.location_on_rounded),
                    size: 16,
                    color: isCompleted
                        ? AppTheme.emeraldGreen
                        : (isCurrent ? AppTheme.accentCyan : c.textMuted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Stop ${idx + 1}: ${isPickup ? 'Pick up' : 'Drop off'} (${w['address'] ?? ''})',
                      style: TextStyle(
                        fontSize: layout.fontSize(11),
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        color: isCompleted ? c.textMuted : (isDark ? Colors.white : c.textPrimary),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (activeWaypoint != null) ...[
            const SizedBox(height: 6),
            if (activeWaypoint['type'] == 'pickup') ...[
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: layout.touchTarget(42),
                      child: TextField(
                        controller: _viewModel.pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Enter 4-Digit PIN',
                          hintStyle: TextStyle(fontSize: layout.fontSize(11)),
                          contentPadding: EdgeInsets.zero,
                          filled: true,
                          fillColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emeraldGreen),
                    onPressed: () async {
                      await _viewModel.verifyAndCompleteWaypoint(
                        rideProv: rideProv,
                        enteredPin: _viewModel.pinController.text,
                        authProv: authProv,
                        driverProv: driverProv,
                      );
                      setState(() {});
                    },
                    child: const Text('Verify PIN'),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: layout.touchTarget(42),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emeraldGreen),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text('Complete Stop ${activeIndex + 1} Dropoff'),
                  onPressed: () async {
                    await _viewModel.verifyAndCompleteWaypoint(
                      rideProv: rideProv,
                      enteredPin: '',
                      authProv: authProv,
                      driverProv: driverProv,
                    );
                    setState(() {});
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
