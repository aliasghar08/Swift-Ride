import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/models/location_point_model.dart';
import '../../domain/models/payment_rail.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_offer_model.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/trip_economics_model.dart';
import '../../domain/models/vehicle_type.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/safety_provider.dart';
import '../../services/firestore/firestore_driver_service.dart';
import '../../services/firestore/firestore_user_service.dart';
import '../../services/map_service.dart';

import '../common/confirm_action.dart';
import '../common/glass_container.dart';
import '../common/google_map_view.dart';
import '../common/map_markers.dart';
import '../common/staggered_animation.dart';
import '../view_models/responsive_layout_helper.dart';
import '../view_models/rider_view_model.dart';
import 'address_search_screen.dart';
import 'route_preview_screen.dart';
import '../widgets/trip_economics_sheet.dart';
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

  bool _waitingForGps = true;
  bool _userCustomPickup = false;
  VoidCallback? _locProvListener;
  LocationProvider? _attachedLocProv;

  // Choose on Map & Camera Pinning State
  bool _isPinningOnMap = false;
  bool _isPinningDestination = true;
  LatLng _mapCenterLocation = const LatLng(31.2785, 72.3317);
  String _pinnedAddress = '';
  Timer? _cameraIdleDebounce;

  // UI Minimization States
  bool _isTopCardMinimized = false;
  final DraggableScrollableController _fareSheetController =
      DraggableScrollableController();
  final DraggableScrollableController _activeRideSheetController =
      DraggableScrollableController();

  bool _userMovedMap = false;
  String? _lastRouteId;

  void _fitSelectedRoute() {
    final sel = _viewModel.selectedRoute;
    final ctrl = _mapController;
    if (sel == null || sel.polylinePoints.isEmpty || ctrl == null) return;
    final points = sel.polylinePoints;
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
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  @override
  void initState() {
    super.initState();
    _viewModel = RiderViewModel();
    MapMarkers.ensureOriginDot();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locProv = CustomChangeNotifierProvider.of<LocationProvider>(
        context,
      );
      _attachedLocProv = locProv;

      final fix = await locProv.waitForFirstFix(
        timeout: const Duration(seconds: 4),
      );
      if (!mounted) return;

      final lat = fix?.latitude ?? locProv.latitude;
      final lng = fix?.longitude ?? locProv.longitude;
      _viewModel.initializeFromCoordinates(lat, lng);
      setState(() => _waitingForGps = false);

      _locProvListener = () {
        if (!mounted || _userCustomPickup) return;
        if (locProv.hasRealFix) {
          final cur = _viewModel.pickupLocation;
          if (cur == null ||
              (cur.latitude - locProv.latitude).abs() > 0.0001 ||
              (cur.longitude - locProv.longitude).abs() > 0.0001) {
            _viewModel.initializeFromCoordinates(
              locProv.latitude,
              locProv.longitude,
            );
          }
        }
      };
      locProv.addListener(_locProvListener!);
    });
  }

  void _ensureDriverPhone(String? driverId) {
    if (driverId == null || driverId == _driverPhoneForDriverId) return;
    _driverPhoneForDriverId = driverId;
    _driverPhone = null;

    FirestoreUserService()
        .getUser(driverId)
        .then((user) {
          if (!mounted || _driverPhoneForDriverId != driverId) return;
          setState(() {
            _driverPhone = user?.phone;
            _driverName = user?.fullName;
          });
        })
        .catchError((Object e) {
          debugPrint('[RiderHome] driver lookup failed: $e');
        });

    FirestoreDriverService()
        .getDriverProfile(driverId)
        .then((profile) {
          if (!mounted ||
              _driverPhoneForDriverId != driverId ||
              profile == null) {
            return;
          }
          final v = profile.vehicle;
          final summary = [
            v.color,
            v.make,
            v.model,
          ].where((p) => p.trim().isNotEmpty).join(' ');
          final plate = v.plate.isEmpty ? '' : ' (${v.plate})';
          final rating = profile.rating > 0
              ? ' • ★ ${profile.rating.toStringAsFixed(2)}'
              : '';
          setState(() {
            _driverVehicle = summary.isEmpty ? null : '$summary$plate$rating';
          });
        })
        .catchError((Object e) {
          debugPrint('[RiderHome] driver profile lookup failed: $e');
        });
  }

  Future<void> _openAddressSearch({required bool isPickup}) async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => AddressSearchScreen(
          title: isPickup ? 'Set Pickup Location' : 'Set Destination',
          initialQuery: isPickup
              ? (_userCustomPickup ? _viewModel.pickupController.text : '')
              : _viewModel.dropoffLocation?.address ?? _viewModel.dropoffController.text,
          isPickup: isPickup,
        ),
      ),
    );
    if (!mounted || result == null) return;

    if ((result is Map && result['chooseOnMap'] == true) ||
        (result is LocationPoint && result.address == '__CHOOSE_ON_MAP__')) {
      final isPick = (result is Map && result.containsKey('isPickup'))
          ? (result['isPickup'] as bool)
          : isPickup;
      _startPinPicking(isPickup: isPick);
      return;
    }

    final point = result as LocationPoint;
    if (isPickup) {
      _userCustomPickup = true;
      _userMovedMap = false;
      _lastRouteId = null;
      await _viewModel.setPickup(point);
      if (_viewModel.dropoffLocation == null) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(point.latitude, point.longitude),
              zoom: 16.0,
            ),
          ),
        );
      }
    } else {
      if (_viewModel.pickupLocation == null) {
        final loc = CustomChangeNotifierProvider.of<LocationProvider>(context);
        _viewModel.initializeFromCoordinates(loc.latitude, loc.longitude);
      }
      _userMovedMap = false;
      _lastRouteId = null;
      await _viewModel.setDestination(point);
      if (_fareSheetController.isAttached) {
        _fareSheetController.animateTo(
          0.45,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _startPinPicking({required bool isPickup}) {
    setState(() {
      _isPinningOnMap = true;
      _isPinningDestination = !isPickup;
    });
    final current = isPickup ? _viewModel.pickupLocation : _viewModel.dropoffLocation;
    _viewModel.startPinPicker(
      isPickup: isPickup,
      initialPoint: current,
    );
    if (current != null) {
      _mapCenterLocation = LatLng(current.latitude, current.longitude);
      _pinnedAddress = current.address;
      if (_mapController != null) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(current.latitude, current.longitude),
              zoom: 16.5,
            ),
          ),
        );
      }
    } else {
      try {
        final loc = CustomChangeNotifierProvider.read<LocationProvider>(context);
        _mapCenterLocation = LatLng(loc.latitude, loc.longitude);
      } catch (_) {}
      _pinnedAddress = 'Positioning pin...';
    }
  }

  void _cancelPinPicking() {
    _cameraIdleDebounce?.cancel();
    setState(() {
      _isPinningOnMap = false;
    });
    _viewModel.cancelPinPicker();
  }

  Future<void> _confirmAndApplyPin() async {
    final isPickup = _isPinningOnMap ? !_isPinningDestination : _viewModel.isPinningPickup;
    final lat = _mapCenterLocation.latitude;
    final lng = _mapCenterLocation.longitude;
    final addr = _pinnedAddress.trim().isNotEmpty
        ? _pinnedAddress
        : (_viewModel.tempPinLocation?.address.trim().isNotEmpty ?? false
            ? _viewModel.tempPinLocation!.address
            : '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}');

    final point = LocationPoint(
      latitude: lat,
      longitude: lng,
      address: addr,
    );

    setState(() {
      _isPinningOnMap = false;
    });

    if (!isPickup && _viewModel.pickupLocation == null) {
      final loc = CustomChangeNotifierProvider.of<LocationProvider>(context);
      _viewModel.initializeFromCoordinates(loc.latitude, loc.longitude);
    }
    _viewModel.confirmPinLocation();
    _userMovedMap = false;
    _lastRouteId = null;

    if (isPickup) {
      _userCustomPickup = true;
      await _viewModel.setPickup(point);
    } else {
      await _viewModel.setDestination(point);
      if (_fareSheetController.isAttached) {
        _fareSheetController.animateTo(
          0.45,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_viewModel.selectedRoute != null &&
          _viewModel.selectedRoute!.polylinePoints.isNotEmpty) {
        _fitSelectedRoute();
      } else {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(point.latitude, point.longitude),
              zoom: 16.0,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _cameraIdleDebounce?.cancel();
    if (_locProvListener != null && _attachedLocProv != null) {
      _attachedLocProv!.removeListener(_locProvListener!);
      _locProvListener = null;
    }
    _fareSheetController.dispose();
    _activeRideSheetController.dispose();
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

        if (rideProv.autoNegotiateBanner != null) {
          final bannerText = rideProv.autoNegotiateBanner!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(bannerText)),
                  ],
                ),
                backgroundColor: AppTheme.emeraldGreen,
                duration: const Duration(seconds: 4),
              ),
            );
            rideProv.clearAutoNegotiateBanner();
          });
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctrl = _mapController;
          if (ctrl == null || currentRide != null) return;
          final sel = _viewModel.selectedRoute;
          if (sel != null && sel.polylinePoints.isNotEmpty) {
            final routeId =
                '${_viewModel.selectedRouteIndex}_${sel.polylinePoints.length}_${sel.distanceKm}';
            if (!_userMovedMap && _lastRouteId != routeId) {
              _lastRouteId = routeId;
              _fitSelectedRoute();
            }
          }
        });

        const casingWidth = 15;
        const fillWidth = 10;

        final polylines = <Polyline>{
          if (_viewModel.routeError == null) ...[
            if (_viewModel.routes.isNotEmpty) ...[
              for (var i = 0; i < _viewModel.routes.length; i++)
                if (i != _viewModel.selectedRouteIndex)
                  Polyline(
                    polylineId: PolylineId('rider_route_$i'),
                    points: _viewModel.routes[i].polylinePoints,
                    color: const Color(0xFF94A3B8).withValues(alpha: 0.65),
                    width: 7,
                    jointType: JointType.round,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    geodesic: true,
                    zIndex: -1,
                  ),
              if (_viewModel.selectedRoute != null) ...[
                Polyline(
                  polylineId: PolylineId(
                    'rider_route_${_viewModel.selectedRouteIndex}_casing',
                  ),
                  points: _viewModel.selectedRoute!.polylinePoints,
                  color: AppTheme.darkNavy,
                  width: casingWidth,
                  jointType: JointType.round,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  geodesic: true,
                  zIndex: 0,
                ),
                Polyline(
                  polylineId: PolylineId(
                    'rider_route_${_viewModel.selectedRouteIndex}_fill',
                  ),
                  points: _viewModel.selectedRoute!.polylinePoints,
                  color: AppTheme.accentCyan,
                  width: fillWidth,
                  jointType: JointType.round,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  geodesic: true,
                  zIndex: 1,
                ),
                ...TrafficInterval.segment(
                  _viewModel.selectedRoute!.polylinePoints,
                  _viewModel.selectedRoute!.trafficIntervals,
                ).asMap().entries.map((entry) {
                  final interval = entry.value.interval;
                  return Polyline(
                    polylineId: PolylineId(
                      'rider_route_${_viewModel.selectedRouteIndex}_traffic_${entry.key}',
                    ),
                    points: entry.value.points,
                    color: _trafficColour(interval),
                    width: fillWidth,
                    jointType: JointType.round,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    geodesic: true,
                    zIndex: 2,
                  );
                }),
              ],
            ] else if (_viewModel.routePolyline.isNotEmpty) ...[
              Polyline(
                polylineId: const PolylineId(
                  'rider_preview_route_casing',
                ),
                points: _viewModel.routePolyline,
                color: AppTheme.darkNavy,
                width: casingWidth,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                geodesic: true,
                zIndex: 0,
              ),
              Polyline(
                polylineId: const PolylineId(
                  'rider_preview_route_fill',
                ),
                points: _viewModel.routePolyline,
                color: AppTheme.accentCyan,
                width: fillWidth,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                geodesic: true,
                zIndex: 1,
              ),
              ...TrafficInterval.segment(
                _viewModel.routePolyline,
                _viewModel.routeTraffic,
              ).asMap().entries.map((entry) {
                final interval = entry.value.interval;
                return Polyline(
                  polylineId: PolylineId(
                    'rider_preview_traffic_${entry.key}',
                  ),
                  points: entry.value.points,
                  color: _trafficColour(interval),
                  width: fillWidth,
                  jointType: JointType.round,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  geodesic: true,
                  zIndex: 2,
                );
              }),
            ],
          ] else if (currentRide != null) ...[
            Polyline(
              polylineId: const PolylineId('rider_active_route_casing'),
              points: [
                if (driverTelemetry != null && !driverTelemetry.isStale)
                  LatLng(
                    driverTelemetry.latitude,
                    driverTelemetry.longitude,
                  )
                else
                  LatLng(
                    currentRide.pickup.latitude,
                    currentRide.pickup.longitude,
                  ),
                LatLng(
                  currentRide.pickup.latitude,
                  currentRide.pickup.longitude,
                ),
                LatLng(
                  currentRide.dropoff.latitude,
                  currentRide.dropoff.longitude,
                ),
              ],
              color: AppTheme.darkNavy,
              width: casingWidth,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              geodesic: true,
              zIndex: 0,
            ),
            Polyline(
              polylineId: const PolylineId('rider_active_route_fill'),
              points: [
                if (driverTelemetry != null && !driverTelemetry.isStale)
                  LatLng(
                    driverTelemetry.latitude,
                    driverTelemetry.longitude,
                  )
                else
                  LatLng(
                    currentRide.pickup.latitude,
                    currentRide.pickup.longitude,
                  ),
                LatLng(
                  currentRide.pickup.latitude,
                  currentRide.pickup.longitude,
                ),
                LatLng(
                  currentRide.dropoff.latitude,
                  currentRide.dropoff.longitude,
                ),
              ],
              color: AppTheme.accentCyan,
              width: fillWidth,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              geodesic: true,
              zIndex: 1,
            ),
          ],
        };

        for (final p in polylines) {
          debugPrint(
            '[POLY-DEBUG] id=${p.polylineId.value} width=${p.width} points=${p.points.length}',
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              Listener(
                onPointerDown: (_) {
                  if (!_userMovedMap && !_isPinningOnMap && !_viewModel.isPinMode) {
                    setState(() => _userMovedMap = true);
                  }
                },
                child: GoogleMapView(
                  initialCenter: LatLng(locProv.latitude, locProv.longitude),
                  initialZoom: 15,
                  showCenterPin: false,
                  semanticsLabel: (_isPinningOnMap || _viewModel.isPinMode)
                      ? 'Map with a pin at the centre. Drag to choose a location.'
                      : (currentRide != null
                            ? 'Live map of your trip. Status: ${currentRide.status.displayName}.'
                            : 'Map of your area. Choose a pickup and destination to see a route.'),
                  mode: (_isPinningOnMap || _viewModel.isPinMode)
                      ? MapMode.pinPicker
                      : (currentRide != null
                            ? MapMode.liveTracking
                            : MapMode.viewOnly),
                  darkMode: true,
                  showTraffic: true,
                  onControllerCreated: (controller) {
                    _mapController = controller;
                  },
                  onCameraMove: (target) {
                    _mapCenterLocation = target;
                  },
                  onPinChanged: (coords) {
                    _mapCenterLocation = coords;
                    _viewModel.updatePinnedCoordinates(
                      coords.latitude,
                      coords.longitude,
                    );
                  },
                  onCameraIdle: (coords) {
                    _mapCenterLocation = coords;
                    _cameraIdleDebounce?.cancel();
                    _cameraIdleDebounce = Timer(const Duration(milliseconds: 300), () async {
                      if (!mounted) return;
                      try {
                        final address = await MapService.instance.reverseGeocode(
                          coords.latitude,
                          coords.longitude,
                        );
                        if (!mounted) return;
                        setState(() {
                          _pinnedAddress = address;
                        });
                      } catch (e) {
                        debugPrint('[RiderHome] reverseGeocode error: $e');
                      }
                    });
                    _viewModel.updatePinnedCoordinates(
                      coords.latitude,
                      coords.longitude,
                    );
                  },
                  markers: {
                    if (currentRide == null &&
                        _viewModel.dropoffLocation != null &&
                        _viewModel.pickupLocation != null) ...[
                      MapMarkers.originDot(
                        LatLng(
                          _viewModel.pickupLocation!.latitude,
                          _viewModel.pickupLocation!.longitude,
                        ),
                        id: 'route_origin_dot',
                      ),
                      MapMarkers.dropoff(
                        LatLng(
                          _viewModel.dropoffLocation!.latitude,
                          _viewModel.dropoffLocation!.longitude,
                        ),
                        id: 'search_dropoff',
                      ),
                    ] else ...[
                      if (currentRide == null &&
                          _viewModel.pickupLocation != null)
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
                    ],
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
                  polylines: polylines,
                ),
              ),

              if (currentRide == null && !_isPinningOnMap && !_viewModel.isPinMode)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: layout.maxCardWidth,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: layout.horizontalPadding,
                          vertical: layout.scale(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildAddressCard(layout),
                            if (_waitingForGps) ...[
                              SizedBox(height: layout.scale(6)),
                              _buildGpsBanner(layout),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              if (_isPinningOnMap || _viewModel.isPinMode) ...[
                // Centered Pin Pointer that stays anchored while map drags beneath it
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Ground contact target ring / shadow pulse at dead center
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: ((_isPinningOnMap
                                            ? !_isPinningDestination
                                            : _viewModel.isPinningPickup)
                                        ? AppTheme.emeraldGreen
                                        : AppTheme.sunsetCoral)
                                    .withValues(alpha: 0.8),
                                width: 2,
                              ),
                            ),
                          ),
                          // Pin Needle & Mode Pill anchored above center
                          Padding(
                            padding: const EdgeInsets.only(bottom: 36.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildPinPickerTooltip(layout),
                                const SizedBox(height: 2),
                                Icon(
                                  Icons.location_pin,
                                  size: 46,
                                  color: (_isPinningOnMap
                                          ? !_isPinningDestination
                                          : _viewModel.isPinningPickup)
                                      ? AppTheme.emeraldGreen
                                      : AppTheme.sunsetCoral,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Dedicated Top Bar for Pin Picker Mode
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: _buildPinPickerTopBar(layout),
                  ),
                ),
                // Dedicated Bottom Sheet for Pin Picker Mode
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: _buildPinPickerBottomBar(layout, locProv),
                  ),
                ),
              ],

              if (!_isPinningOnMap &&
                  !_viewModel.isPinMode &&
                  (currentRide != null || _viewModel.dropoffLocation != null))
                Positioned.fill(
                  child: currentRide == null
                      ? _buildFareProposalSheet(
                          layout,
                          rideProv,
                          authProv,
                          driverProv,
                        )
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
                        constraints: BoxConstraints(
                          maxWidth: layout.maxCardWidth,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.horizontalPadding,
                            vertical: layout.scale(8),
                          ),
                          child: SafetyCheckOverlay(
                            rideId:
                                safetyCheck.rideId ??
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
              if (_userMovedMap) ...[
                FloatingActionButton.small(
                  heroTag: 'my_location_btn',
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.accentCyan,
                  child: const Icon(Icons.my_location, size: 20),
                  onPressed: () {
                    setState(() {
                      _userMovedMap = false;
                    });
                    if (_viewModel.selectedRoute != null) {
                      _fitSelectedRoute();
                    } else {
                      final loc =
                          CustomChangeNotifierProvider.read<LocationProvider>(
                            context,
                          );
                      _userCustomPickup = false;
                      _viewModel.initializeFromCoordinates(
                        loc.latitude,
                        loc.longitude,
                      );
                      if (_mapController != null) {
                        _mapController!.animateCamera(
                          CameraUpdate.newLatLngZoom(
                            LatLng(loc.latitude, loc.longitude),
                            15.5,
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              FloatingActionButton.small(
                heroTag: 'ride_history_btn',
                tooltip: 'My Trips',
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: AppTheme.accentCyan,
                child: const Icon(Icons.history_rounded, size: 20),
                onPressed: () => Navigator.of(context).pushNamed('/history'),
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
                  label: const Text(
                    'Ask AI',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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

  static String _formatDriverNumber(double val) {
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  Widget _buildRouteSelector(ResponsiveLayoutHelper layout) {
    if (_viewModel.routes.length <= 1) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_viewModel.routes.length, (i) {
          final route = _viewModel.routes[i];
          final isSelected = i == _viewModel.selectedRouteIndex;

          final labelText = route.labels.isNotEmpty
              ? route.labels.map((l) {
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
              : 'Alternative';

          final distText = route.distanceKm % 1 == 0
              ? route.distanceKm.toInt().toString()
              : route.distanceKm.toStringAsFixed(1);
          final fareText = route.economics.riderFare % 1 == 0
              ? route.economics.riderFare.toInt().toString()
              : route.economics.riderFare.toStringAsFixed(0);
          final line2Text =
              '$distText km · ${route.durationMin.round()} min · PKR $fareText';

          final Color buttonBg = isSelected
              ? AppTheme.primaryBlue
              : (isDark ? c.surfaceRaised : const Color(0xFFF1F5F9));

          final isBgDark =
              ThemeData.estimateBrightnessForColor(buttonBg) == Brightness.dark;

          final Color titleColor = isSelected
              ? Colors.white
              : (isBgDark ? c.textPrimary : const Color(0xFF0F172A));

          final Color subtitleColor = isSelected
              ? Colors.white.withValues(alpha: 0.9)
              : (isBgDark ? c.textSecondary : const Color(0xFF475569));

          final Color borderColor = isSelected
              ? (isDark ? AppTheme.accentCyan : AppTheme.primaryBlue)
              : c.border;

          return Padding(
            padding: EdgeInsets.only(
              right: i < _viewModel.routes.length - 1 ? 8.0 : 0,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _viewModel.selectRoute(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: buttonBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor,
                      width: isSelected ? 2.0 : 1.2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labelText,
                        style: TextStyle(
                          fontSize: layout.fontSize(12),
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        line2Text,
                        style: TextStyle(
                          fontSize: layout.fontSize(11),
                          fontWeight: FontWeight.w500,
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGpsBanner(ResponsiveLayoutHelper layout) {
    return GlassContainer(
      borderRadius: 16,
      blur: 14,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accentCyan,
            ),
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
    );
  }

  Widget _buildAddressCard(ResponsiveLayoutHelper layout) {
    if (_isTopCardMinimized) {
      return GestureDetector(
        onTap: () => setState(() => _isTopCardMinimized = false),
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 100) {
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
                style: TextStyle(
                  color: AppColors.of(context).textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -100) {
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
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.radio_button_checked,
                    color: AppTheme.emeraldGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openAddressSearch(isPickup: true),
                      child: IgnorePointer(
                        child: TextField(
                          controller: _viewModel.pickupController,
                          style: TextStyle(
                            color: AppColors.of(context).textPrimary,
                            fontSize: layout.fontSize(14),
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Pickup Location',
                            hintStyle: TextStyle(
                              color: AppColors.of(context).textMuted,
                              fontSize: layout.fontSize(14),
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppTheme.emeraldGreen,
                    ),
                    icon: const Icon(Icons.pin_drop_rounded, size: 16),
                    label: const Text(
                      'Map',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => _startPinPicking(isPickup: true),
                  ),
                ],
              ),
              const Divider(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: AppTheme.sunsetCoral,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openAddressSearch(isPickup: false),
                      child: IgnorePointer(
                        child: TextField(
                          controller: _viewModel.dropoffController,
                          style: TextStyle(
                            color: AppColors.of(context).textPrimary,
                            fontSize: layout.fontSize(14),
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Where to? (Destination)',
                            hintStyle: TextStyle(
                              color: AppColors.of(context).textMuted,
                              fontSize: layout.fontSize(14),
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppTheme.sunsetCoral,
                    ),
                    icon: const Icon(Icons.pin_drop_rounded, size: 16),
                    label: const Text(
                      'Map',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => _startPinPicking(isPickup: false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinPickerTooltip(ResponsiveLayoutHelper layout) {
    final isPickup = _isPinningOnMap ? !_isPinningDestination : _viewModel.isPinningPickup;
    final isResolving = _viewModel.isResolvingPinAddress && _pinnedAddress.isEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isResolving
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: isPickup
                        ? AppTheme.emeraldGreen
                        : AppTheme.sunsetCoral,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Locating...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          : Text(
              isPickup ? 'Set Pickup' : 'Set Destination',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildPinPickerTopBar(ResponsiveLayoutHelper layout) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);
    final isPickup = _isPinningOnMap ? !_isPinningDestination : _viewModel.isPinningPickup;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.horizontalPadding,
        vertical: layout.scale(8),
      ),
      child: GlassContainer(
        backgroundColor: isDark ? c.surfaceRaised : Colors.white.withValues(alpha: 0.95),
        borderColor: c.border,
        isDark: isDark,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              color: c.textPrimary,
              tooltip: 'Cancel Map Pinning',
              onPressed: () => _cancelPinPicking(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isPickup ? 'Choose Pickup Spot on Map' : 'Choose Destination on Map',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  Text(
                    'Drag map to align center pin at exact spot',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _cancelPinPicking(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.sunsetCoral,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinPickerBottomBar(
    ResponsiveLayoutHelper layout,
    LocationProvider locProv,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);
    final isPickup = _isPinningOnMap ? !_isPinningDestination : _viewModel.isPinningPickup;
    final currentAddress = _pinnedAddress.trim().isNotEmpty
        ? _pinnedAddress
        : (_viewModel.tempPinLocation?.address ?? 'Positioning pin...');

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.horizontalPadding,
        vertical: layout.scale(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Floating "Snap to My Location" GPS button
          FloatingActionButton.small(
            heroTag: 'map_picker_gps_locate',
            backgroundColor: isDark ? c.surfaceRaised : Colors.white,
            foregroundColor: AppTheme.primaryBlue,
            elevation: 4,
            tooltip: 'Snap to Current GPS',
            onPressed: () {
              final lat = locProv.latitude;
              final lng = locProv.longitude;
              _mapCenterLocation = LatLng(lat, lng);
              _pinnedAddress = '';
              if (_mapController != null) {
                _mapController!.animateCamera(
                  CameraPosition(
                    target: LatLng(lat, lng),
                    zoom: 16.5,
                  ),
                );
              }
              _viewModel.updatePinnedCoordinates(lat, lng);
            },
            child: const Icon(Icons.my_location_rounded, size: 20),
          ),
          const SizedBox(height: 10),

          // Bottom Confirmation Card
          GlassContainer(
            backgroundColor: isDark ? c.surfaceRaised : Colors.white,
            borderColor: c.border,
            isDark: isDark,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isPickup
                            ? AppTheme.emeraldGreen.withValues(alpha: 0.15)
                            : AppTheme.sunsetCoral.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPickup ? Icons.my_location_rounded : Icons.location_on_rounded,
                        color: isPickup ? AppTheme.emeraldGreen : AppTheme.sunsetCoral,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPickup ? 'PICKUP SPOT' : 'DESTINATION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: isPickup
                                  ? AppTheme.emeraldGreen
                                  : AppTheme.sunsetCoral,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            (_viewModel.isResolvingPinAddress && _pinnedAddress.isEmpty)
                                ? 'Locating...'
                                : currentAddress,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => _confirmAndApplyPin(),
                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                  label: Text(
                    isPickup ? 'Confirm Pickup' : 'Confirm Location',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPickup
                        ? AppTheme.emeraldGreen
                        : AppTheme.sunsetCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFareProposalSheet(
    ResponsiveLayoutHelper layout,
    RideProvider rideProv,
    AuthProvider authProv,
    DriverProvider driverProv,
  ) {
    if (_viewModel.dropoffLocation == null) {
      return const SizedBox.shrink();
    }

    final c = AppColors.of(layout.context);
    final isDark = Theme.of(layout.context).brightness == Brightness.dark;
    final displayedFare =
        _viewModel.selectedEconomics?.riderFare ?? _viewModel.suggestedFare;

    return DraggableScrollableSheet(
      controller: _fareSheetController,
      initialChildSize: 0.45,
      minChildSize: 0.20,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.20, 0.45, 0.92],
      builder: (context, scrollController) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
            child: GlassContainer(
              borderRadius: 28,
              blur: 24,
              backgroundColor: AppColors.of(context).surface,
              gradient: LinearGradient(
                colors: [
                  AppColors.of(context).surface,
                  AppColors.of(context).surface,
                ],
              ),
              padding: EdgeInsets.fromLTRB(
                layout.horizontalPadding,
                14,
                layout.horizontalPadding,
                layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 20,
              ),
              child: CustomScrollView(
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          key: const Key('fare_sheet_drag_handle'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_fareSheetController.isAttached) {
                              final current = _fareSheetController.size;
                              if (current < 0.35) {
                                _fareSheetController.animateTo(
                                  0.45,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              } else if (current < 0.70) {
                                _fareSheetController.animateTo(
                                  0.92,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              } else {
                                _fareSheetController.animateTo(
                                  0.20,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade400,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
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
                                    fontSize: layout.fontSize(12),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              InkWell(
                                onTap: () => _viewModel.applyAiSuggestedFare(),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentCyan.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppTheme.accentCyan.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.auto_awesome,
                                        size: 13,
                                        color: AppTheme.accentCyan,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _viewModel.aiSuggestedSweetSpot != null
                                            ? 'AI Suggested Sweet Spot: ${CurrencyFormatter.format(_viewModel.aiSuggestedSweetSpot!)}'
                                            : 'Suggested: ${CurrencyFormatter.format(displayedFare)}',
                                        style: TextStyle(
                                          color: AppTheme.accentCyan,
                                          fontWeight: FontWeight.w700,
                                          fontSize: layout.fontSize(11.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_viewModel.routeError != null &&
                            _viewModel.dropoffLocation != null) ...[
                          SizedBox(height: layout.scale(10)),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.scale(14),
                              vertical: layout.scale(10),
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.sunsetCoral.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.sunsetCoral.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: AppTheme.sunsetCoral,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _viewModel.routeError!,
                                    style: TextStyle(
                                      color: AppTheme.sunsetCoral,
                                      fontSize: layout.fontSize(12),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_viewModel.routes.length > 1) ...[
                          SizedBox(height: layout.scale(10)),
                          _buildRouteSelector(layout),
                          if (!_viewModel.fareTouchedByUser &&
                              _viewModel.selectedEconomics != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Driver earns PKR ${_formatDriverNumber(_viewModel.selectedEconomics!.driverProfit)} (${_formatDriverNumber(_viewModel.selectedEconomics!.profitPerMin)} PKR/min)',
                              style: const TextStyle(
                                color: AppTheme.slateMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                        if (_viewModel.selectedRoute != null) ...[
                          SizedBox(height: layout.scale(8)),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RoutePreviewScreen(viewModel: _viewModel),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.directions,
                                size: 18,
                                color: AppTheme.accentCyan,
                              ),
                              label: const Text(
                                'Directions',
                                style: TextStyle(
                                  color: AppTheme.accentCyan,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
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
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: layout.scale(12)),
                        StaggeredEntryWidget(
                          index: 1,
                          child: _buildVehicleTypeSelector(layout),
                        ),
                        SizedBox(height: layout.scale(14)),
                        StaggeredEntryWidget(
                          index: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Offer (Rider sets the price):',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: layout.fontSize(14),
                                ),
                              ),
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
                                    child: Text(
                                      'PKR',
                                      style: TextStyle(
                                        fontSize: layout.fontSize(14),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: layout.touchTarget(48),
                                      child: TextField(
                                        controller: _viewModel.fareController,
                                        keyboardType: const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        onChanged: (_) => _viewModel.markFareEditedByUser(),
                                        style: TextStyle(
                                          fontSize: layout.fontSize(18),
                                          fontWeight: FontWeight.bold,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: 'Enter fare in PKR',
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
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
                        SizedBox(height: layout.scale(8)),
                        // Auto-Negotiate Bot Switch & Ceiling Selector
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _viewModel.isAutoNegotiateEnabled
                                ? AppTheme.accentCyan.withValues(alpha: 0.12)
                                : c.surfaceRaised,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _viewModel.isAutoNegotiateEnabled
                                  ? AppTheme.accentCyan.withValues(alpha: 0.4)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.smart_toy_rounded,
                                    color: _viewModel.isAutoNegotiateEnabled
                                        ? AppTheme.accentCyan
                                        : c.textSecondary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Auto-Accept Offers',
                                          style: TextStyle(
                                            fontSize: layout.fontSize(13),
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : c.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Automatically accept any driver offer up to PKR ${(_viewModel.maxAutoFare ?? ((double.tryParse(_viewModel.fareController.text) ?? _viewModel.suggestedFare) * 1.2 / 10).round() * 10).toInt()}',
                                          style: TextStyle(
                                            fontSize: layout.fontSize(11),
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _viewModel.isAutoNegotiateEnabled,
                                    activeThumbColor: AppTheme.accentCyan,
                                    onChanged: (val) {
                                      _viewModel.setAutoNegotiate(val);
                                    },
                                  ),
                                ],
                              ),
                              if (_viewModel.isAutoNegotiateEnabled) ...[
                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      Text(
                                        'Budget Ceiling:',
                                        style: TextStyle(
                                          fontSize: layout.fontSize(11),
                                          fontWeight: FontWeight.w600,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ...[10, 20, 30].map((percent) {
                                        final base = double.tryParse(_viewModel.fareController.text) ??
                                            _viewModel.suggestedFare;
                                        final targetCeiling =
                                            (((base * (1 + percent / 100)) / 10).round() * 10).toDouble();
                                        final isSelected =
                                            (_viewModel.maxAutoFare ?? 0).toInt() == targetCeiling.toInt();
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: ChoiceChip(
                                            label: Text(
                                              '+$percent% (PKR ${targetCeiling.toInt()})',
                                              style: TextStyle(
                                                fontSize: layout.fontSize(10),
                                                fontWeight: FontWeight.w600,
                                                color: isSelected ? Colors.white : c.textPrimary,
                                              ),
                                            ),
                                            selected: isSelected,
                                            selectedColor: AppTheme.accentCyan,
                                            onSelected: (selected) {
                                              if (selected) {
                                                _viewModel.setMaxAutoFare(targetCeiling);
                                              }
                                            },
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: layout.scale(10)),
                        StaggeredEntryWidget(
                          index: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: c.surfaceRaised,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.credit_card,
                                  size: 16,
                                  color: AppTheme.primaryBlue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Payment: ${_viewModel.selectedPaymentMethod}',
                                    style: TextStyle(
                                      fontSize: layout.fontSize(12),
                                      fontWeight: FontWeight.w600,
                                      color: c.textSecondary,
                                    ),
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
                                      fontWeight: FontWeight.bold,
                                    ),
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
                              boxShadow: AppTheme.glowShadow(
                                AppTheme.primaryBlue,
                                opacity: 0.35,
                                blur: 16,
                              ),
                            ),
                            height: layout.touchTarget(50),
                            child: ElevatedButton(
                              onPressed: rideProv.isSubmitting
                                  ? null
                                  : () async {
                                      final ok = await _viewModel.submitRideRequest(
                                        rideProv: rideProv,
                                      );
                                      if (!mounted || !context.mounted || ok) return;
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
                ],
              ),
            ),
          ),
        );
      },
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
    return DraggableScrollableSheet(
      controller: _activeRideSheetController,
      initialChildSize: 0.45,
      minChildSize: 0.20,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.20, 0.45, 0.92],
      builder: (context, scrollController) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.maxCardWidth),
            child: GlassContainer(
              borderRadius: 28,
              blur: 24,
              backgroundColor: AppColors.of(context).surface,
              gradient: LinearGradient(
                colors: [
                  AppColors.of(context).surface,
                  AppColors.of(context).surface,
                ],
              ),
              padding: EdgeInsets.fromLTRB(
                layout.horizontalPadding,
                14,
                layout.horizontalPadding,
                layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 20,
              ),
              child: CustomScrollView(
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          key: const Key('active_ride_sheet_drag_handle'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_activeRideSheetController.isAttached) {
                              final current = _activeRideSheetController.size;
                              if (current < 0.35) {
                                _activeRideSheetController.animateTo(
                                  0.45,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              } else if (current < 0.70) {
                                _activeRideSheetController.animateTo(
                                  0.92,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              } else {
                                _activeRideSheetController.animateTo(
                                  0.20,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade400,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: layout.scale(10)),
            StaggeredEntryWidget(
              index: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sync,
                          color: AppTheme.primaryBlue,
                          size: 16,
                        ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.darkNavy,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: AppTheme.glowShadow(
                        AppTheme.accentCyan,
                        opacity: 0.25,
                        blur: 8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: AppTheme.accentCyan,
                          size: 16,
                        ),
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
                  Text(
                    'Incoming Driver Offers:',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: layout.fontSize(14),
                    ),
                  ),
                  Text(
                    '${offers.length} drivers nearby',
                    style: TextStyle(
                      color: AppTheme.slateMuted,
                      fontSize: layout.fontSize(12),
                    ),
                  ),
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
                  backgroundColor: AppColors.of(context).surfaceRaised,
                  borderColor: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primaryBlue.withValues(
                          alpha: 0.1,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: AppTheme.primaryBlue,
                        ),
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
                                color: AppColors.of(context).textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: layout.fontSize(13),
                              ),
                            ),
                            Text(
                              _driverVehicle ??
                                  (ride.driverId == null
                                      ? 'Waiting for a driver to accept'
                                      : 'Loading vehicle details…'),
                              style: TextStyle(
                                fontSize: layout.fontSize(11),
                                color: AppColors.of(context).textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(
                          ride.acceptedFare ?? ride.offeredFare,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: layout.fontSize(15),
                          color: AppTheme.emeraldGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Live Trip Economics & Fuel Calculation Card for Rider
              Builder(
                builder: (ctx) {
                  final vType = VehicleTypeX.fromString(ride.vehicleType);
                  final econ = TripEconomics.calculate(
                    vehicleType: vType,
                    distanceKm: ride.distanceKm,
                    durationMin: ride.durationMin,
                    fare: ride.acceptedFare ?? ride.offeredFare,
                    bookedSeats: ride.bookedSeats,
                    isAiPredicted: true,
                  );
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => TripEconomicsSheet.show(
                      context,
                      economics: econ,
                      isDriverView: false,
                    ),
                    child: Container(
                      margin: EdgeInsets.only(top: layout.scale(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.emeraldGreen.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.analytics_rounded, size: 15, color: AppTheme.emeraldGreen),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '⛽ Fuel: Rs ${econ.fuelCost.toInt()} • 🔧 Maint: Rs ${econ.maintenanceCost.toInt()} • 💰 Driver: Rs ${econ.driverNetProfit.toInt()}',
                              style: TextStyle(
                                fontSize: layout.fontSize(11),
                                color: AppTheme.emeraldGreen,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: AppTheme.emeraldGreen,
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
                    color: AppTheme.sunsetCoral.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emergency,
                      color: AppTheme.sunsetCoral,
                      size: 18,
                    ),
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
                        backgroundColor: AppTheme.emeraldGreen.withValues(
                          alpha: 0.15,
                        ),
                        foregroundColor: AppTheme.emeraldGreen,
                      ),
                      icon: const Icon(Icons.phone),
                      tooltip: 'Call Driver',
                      onPressed: () => _showCallDriverSheet(context, layout),
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
                          if (!mounted || !context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                url != null ? 'Trip share link ready: $url' : 'We could not create a share link. Check your connection and try again.',
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
                          backgroundColor: AppTheme.sunsetCoral.withValues(
                            alpha: 0.18,
                          ),
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
                          message: 'Your driver may already be on the way. Cancelling after a driver has accepted can incur a cancellation fee.',
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
      ],
    ),
  ),
),
);
},
);
}

  Widget _buildVehicleTypeSelector(ResponsiveLayoutHelper layout) {
    final c = AppColors.of(layout.context);
    final selectedType = _viewModel.selectedVehicleType;
    final fares = _viewModel.vehicleFares;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Vehicle Category:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: layout.fontSize(13.5),
                color: c.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '0% Commission',
                style: TextStyle(
                  fontSize: layout.fontSize(10.5),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.emeraldGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: VehicleType.values.map((type) {
            final isSelected = type == selectedType;
            final fare = fares[type] ?? type.calculateFare(_viewModel.suggestedFare);

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: type == VehicleType.values.last ? 0 : 8,
                ),
                child: InkWell(
                  onTap: () => _viewModel.selectVehicleType(type),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                          : c.surfaceRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryBlue
                            : Colors.grey.withValues(alpha: 0.25),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.22),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryBlue
                                    : c.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                type.icon,
                                size: layout.scale(22),
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.slateMuted,
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.emeraldGreen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          type.title.split(' ').first,
                          style: TextStyle(
                            fontSize: layout.fontSize(12.5),
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? AppTheme.primaryBlue : c.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person,
                              size: 10.5,
                              color: isSelected
                                  ? AppTheme.primaryBlue.withValues(alpha: 0.8)
                                  : AppTheme.slateMuted,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${type.seats}',
                              style: TextStyle(
                                fontSize: layout.fontSize(10),
                                color: AppTheme.slateMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '• ~${type.typicalEtaMinutes}m',
                              style: TextStyle(
                                fontSize: layout.fontSize(10),
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryBlue
                                : c.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'PKR ${fare.round()}',
                            style: TextStyle(
                              fontSize: layout.fontSize(11.5),
                              fontWeight: FontWeight.w800,
                              color: isSelected
                                  ? Colors.white
                                  : c.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // Seating Selection Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.airline_seat_recline_normal_rounded,
                size: 16,
                color: AppTheme.primaryBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'Seats:',
                style: TextStyle(
                  fontSize: layout.fontSize(12),
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: List.generate(selectedType.seats, (index) {
                    final seatCount = index + 1;
                    final isSelected = seatCount == _viewModel.bookedSeats;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _viewModel.setBookedSeats(seatCount);
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryBlue : c.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppTheme.primaryBlue : c.border,
                            ),
                          ),
                          child: Text(
                            '$seatCount',
                            style: TextStyle(
                              fontSize: layout.fontSize(11.5),
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Text(
                '${_viewModel.bookedSeats} of ${selectedType.seats} ${selectedType.seats == 1 ? 'seat' : 'seats'}',
                style: TextStyle(
                  fontSize: layout.fontSize(11),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Live Trip Economics Preview Card
        InkWell(
          onTap: () {
            TripEconomicsSheet.show(
              context,
              economics: _viewModel.currentTripEconomics,
              onSeatCountChanged: (seats) {
                setState(() {
                  _viewModel.setBookedSeats(seats);
                });
              },
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.emeraldGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.analytics_rounded,
                  size: 16,
                  color: AppTheme.emeraldGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⛽ Fuel: Rs ${_viewModel.currentTripEconomics.fuelCost.toInt()} • 🔧 Maint: Rs ${_viewModel.currentTripEconomics.maintenanceCost.toInt()} • 💰 Driver: Rs ${_viewModel.currentTripEconomics.driverNetProfit.toInt()}',
                    style: TextStyle(
                      fontSize: layout.fontSize(11),
                      fontWeight: FontWeight.w700,
                      color: AppTheme.emeraldGreen,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppTheme.emeraldGreen,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCallDriverSheet(BuildContext context, ResponsiveLayoutHelper layout) {
    final phone = _driverPhone?.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    final name = _driverName ?? 'SwiftRide Driver';
    final vehicle = _driverVehicle ?? 'Verified SwiftRide Vehicle';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final c = AppColors.of(ctx);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              layout.horizontalPadding,
              0,
              layout.horizontalPadding,
              layout.safePadding.bottom > 0 ? layout.safePadding.bottom + 8 : 16,
            ),
            child: GlassContainer(
              borderRadius: 28,
              blur: 24,
              backgroundColor: c.surface,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 30,
                          color: AppTheme.emeraldGreen,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: layout.fontSize(17),
                                fontWeight: FontWeight.bold,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              vehicle,
                              style: TextStyle(
                                fontSize: layout.fontSize(12),
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (phone != null && phone.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.surfaceRaised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.phone_iphone, color: AppTheme.accentCyan, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _driverPhone ?? phone,
                              style: TextStyle(
                                fontSize: layout.fontSize(15.5),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copy Number',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: phone));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Phone number copied: $phone'),
                                  backgroundColor: AppTheme.emeraldGreen,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emeraldGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.call, size: 20),
                      label: Text(
                        'Call Driver Now',
                        style: TextStyle(
                          fontSize: layout.fontSize(15.5),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.of(ctx).pop();
                        final success = await _viewModel.callDriver(phone);
                        if (!success && mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Could not open phone dialer for $phone.'),
                              backgroundColor: AppTheme.sunsetCoral,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.6)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline, size: 19),
                      label: Text(
                        'Send SMS / Text Message',
                        style: TextStyle(
                          fontSize: layout.fontSize(14),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _viewModel.sendDriverSms(
                          phone: phone,
                          message: 'Assalam-o-Alaikum! I am your SwiftRide passenger waiting at the pickup location.',
                        );
                      },
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.sunsetCoral.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.sunsetCoral.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppTheme.sunsetCoral, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Driver phone number is being retrieved from the server...',
                              style: TextStyle(
                                fontSize: layout.fontSize(12.5),
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Fetching Driver Contact'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _driverPhoneForDriverId = null;
                        final active = CustomChangeNotifierProvider.of<RideProvider>(context).activeRide;
                        _ensureDriverPhone(active?.driverId);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOfferCard(
    ResponsiveLayoutHelper layout,
    RideOffer offer,
    RideProvider rideProv,
    int index,
  ) {
    return StaggeredEntryWidget(
      index: index,
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 8),
        borderRadius: 14,
        blur: 12,
        padding: const EdgeInsets.all(12),
        backgroundColor: AppColors.of(context).surfaceRaised,
        borderColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
        shadows: AppTheme.glowShadow(
          AppTheme.primaryBlue,
          opacity: 0.08,
          blur: 10,
        ),
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
                      Text(
                        offer.driverName,
                        style: TextStyle(
                          color: AppColors.of(context).textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(13),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '★ ${offer.driverRating}',
                        style: TextStyle(
                          fontSize: layout.fontSize(11),
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${offer.vehicleSummary} • ${offer.etaMinutes} min away',
                    style: TextStyle(
                      fontSize: layout.fontSize(11),
                      color: AppColors.of(context).textMuted,
                    ),
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
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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
    final ride = CustomChangeNotifierProvider.of<RideProvider>(context)
        .currentRide;

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
              Text(
                'Select Payment Method',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cash is the only method available right now. Online payments are not connected yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: c.textMuted,
                  height: 1.35,
                ),
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
                : c.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryBlue.withValues(alpha: 0.4)
                  : c.border,
            ),
            boxShadow: isSelected
                ? AppTheme.glowShadow(
                    AppTheme.primaryBlue,
                    opacity: 0.1,
                    blur: 8,
                  )
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
              child: Icon(
                rail.icon,
                color: isSelected ? Colors.white : AppTheme.primaryBlue,
                size: 18,
              ),
            ),
            title: Text(
              rail.label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
                color: c.textPrimary,
              ),
            ),
            subtitle: Text(
              enabled
                  ? rail.description
                  : '${rail.description} — not available yet',
              style: TextStyle(fontSize: 11.5, color: c.textMuted),
            ),
            trailing: !enabled
                ? Text(
                    'Coming soon',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textMuted,
                    ),
                  )
                : isSelected
                ? Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.emeraldGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  )
                : null,
            onTap: !enabled
                ? null
                : () async {
                    _viewModel.selectPaymentMethod(rail);
                    Navigator.pop(sheetContext);
                    if (ride != null) {
                      final rideProv =
                          CustomChangeNotifierProvider.of<RideProvider>(
                            context,
                          );
                      final ok = await rideProv.setPaymentMethod(
                        ride.id,
                        rail.id,
                      );
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
      message: 'This tells your driver and trusted contacts that the emergency is over. Only close it if you are genuinely safe.',
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
          error ?? 'Alert closed. Your contacts will see it is resolved.',
        ),
        backgroundColor: error == null
            ? AppTheme.emeraldGreen
            : AppTheme.sunsetCoral,
      ),
    );
  }

  Future<void> _offerSosSms(
    List<String> phones,
    double latitude,
    double longitude,
  ) async {
    if (phones.isEmpty) return;
    final body =
        'SwiftRide emergency. I need help. My live location: '
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
        backgroundColor: opened == 0
            ? AppTheme.sunsetCoral
            : AppTheme.emeraldGreen,
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
          shadows: AppTheme.glowShadow(
            AppTheme.sunsetCoral,
            opacity: 0.35,
            blur: 32,
          ),
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
                      child: const Icon(
                        Icons.warning,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Emergency SOS',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: c.textPrimary,
                      ),
                    ),
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
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                        child: const Text(
                          'Dismiss',
                          style: TextStyle(
                            color: AppTheme.slateMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.sunsetCoral,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
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
                                seconds: result.reachedAnyone ? 4 : 8,
                              ),
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
                        child: const Text(
                          'DISPATCH SOS',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
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
