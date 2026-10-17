import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/native_map_service.dart';
import '../../core/utils/distance_calculator.dart';
import '../../domain/models/location_point_model.dart';
import '../../providers/ride_provider.dart';
import '../../providers/safety_provider.dart';
import '../../services/firestore/firestore_safety_service.dart';
import '../../services/map_service.dart';
import '../../services/native/native_audio_service.dart';
import '../../services/native/native_device_service.dart';
import '../../services/native/native_launcher_service.dart';
import '../../services/native/native_notification_service.dart';
import '../../services/native/native_safety_service.dart';
import '../../domain/models/payment_rail.dart';
import '../../services/pricing_ml_service.dart';

/// ViewModel managing Rider UI state, address search, pin-dropping,
/// route polylines, PKR fare negotiation, and native safety integrations.
class RiderViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final NativeSafetyService _safetyService;
  final NativeNotificationService _notificationService;
  final NativeAudioService _audioService;
  final NativeLauncherService _launcherService;
  final MapService _mapService = MapService();
  final FirestoreSafetyService _safetyEvents = FirestoreSafetyService();
  final PricingMLService _pricingMLService = PricingMLService();

  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController fareController = TextEditingController();

  double? _aiSuggestedSweetSpot;

  double _estimatedDistanceKm = 0;
  double _estimatedDurationMin = 0;

  List<RouteOption> _routes = [];
  int _selectedRouteIndex = 0;

  LocationPoint? _pickupLocation;
  LocationPoint? _dropoffLocation;
  List<LatLng> _routePolyline = [];
  List<TrafficInterval> _routeTraffic = [];

  Timer? _routeDebounce;
  int _routeRequestId = 0;
  bool _fareTouchedByUser = false;
  bool _routeIsEstimated = false;
  String? _routeError;
  bool _isLoadingRoute = false;

  bool _isPinMode = false;
  LocationPoint? _tempPinLocation;
  LocationPoint? get tempPinLocation => _tempPinLocation;
  bool _isResolvingPinAddress = false;
  bool get isResolvingPinAddress => _isResolvingPinAddress;
  bool _isPinningPickup = true;
  bool get isPinningPickup => _isPinningPickup;
  PaymentRail _selectedRail = PaymentRail.fallback;
  bool _isDisposed = false;

  /// True once a real GPS-backed pickup has been set (either from the platform
  /// fix or from the user's own pin/search). False means "we don't actually
  /// know where the rider is" and callers must handle that.
  bool _hasPickupFromGps = false;

  RiderViewModel({
    NativeDeviceService? deviceService,
    NativeSafetyService? safetyService,
    NativeNotificationService? notificationService,
    NativeAudioService? audioService,
    NativeLauncherService? launcherService,
  })  : _deviceService = deviceService ?? NativeDeviceService(),
        _safetyService = safetyService ?? NativeSafetyService(),
        _notificationService = notificationService ?? NativeNotificationService(),
        _audioService = audioService ?? NativeAudioService(),
        _launcherService = launcherService ?? NativeLauncherService();

  bool get isPinMode => _isPinMode;
  bool get isLoadingRoute => _isLoadingRoute;
  LocationPoint? get destination => _dropoffLocation;
  LocationPoint? get pickup => _pickupLocation;
  PaymentRail get selectedRail => _selectedRail;
  String get selectedPaymentMethod => _selectedRail.label;
  double get estimatedDistanceKm => _estimatedDistanceKm;
  double get estimatedDurationMin => _estimatedDurationMin;
  List<LatLng> get routePolyline => _routePolyline;
  List<TrafficInterval> get routeTraffic => _routeTraffic;
  LocationPoint? get pickupLocation => _pickupLocation;
  LocationPoint? get dropoffLocation => _dropoffLocation;

  List<RouteOption> get routes => _routes;
  int get selectedRouteIndex => _selectedRouteIndex;
  RouteOption? get selectedRoute =>
      (_selectedRouteIndex >= 0 && _selectedRouteIndex < _routes.length)
          ? _routes[_selectedRouteIndex]
          : null;
  RouteEconomics? get selectedEconomics => selectedRoute?.economics;
  bool get fareTouchedByUser => _fareTouchedByUser;
  String? get routeError => _routeError;

  /// True once a genuine GPS (or explicit user-chosen) pickup exists.
  bool get hasPickupFromGps => _hasPickupFromGps;

  double get suggestedFare =>
      _aiSuggestedSweetSpot ??
      selectedEconomics?.riderFare ??
      DistanceCalculator.calculateSuggestedFare(_estimatedDistanceKm, _estimatedDurationMin);

  double? get aiSuggestedSweetSpot => _aiSuggestedSweetSpot;

  void applyAiSuggestedFare() {
    if (_aiSuggestedSweetSpot != null) {
      fareController.text = _aiSuggestedSweetSpot!.round().toString();
      _fareTouchedByUser = true;
      _deviceService.triggerHaptic('selection');
      notifyListeners();
    }
  }

  /// Sets the pickup address from a real device fix.
  ///
  /// Callers must pass actual coordinates obtained from
  /// `LocationProvider.waitForFirstFix()`. This method does NOT substitute
  /// invented coordinates — if the caller couldn't get a fix, it should not
  /// call this at all.
  Future<void> initializeFromCoordinates(double lat, double lng) async {
    // Accept the coordinates verbatim. Previously this rewrote anything that
    // matched a Cupertino/SF bounding box to Islamabad, which broke for any
    // real user actually in that region.
    _pickupLocation = LocationPoint(
      latitude: lat,
      longitude: lng,
      address: 'Current Location',
    );
    _hasPickupFromGps = true;
    notifyListeners();

    // Reverse geocode in the background; if it fails, leave the generic
    // "Current Location" string alone rather than inventing a place name.
    try {
      final realAddress = await _mapService.reverseGeocode(lat, lng);
      if (_isDisposed) return;
      if (realAddress.isNotEmpty) {
        pickupController.text = realAddress;
        _pickupLocation = _pickupLocation!.copyWith(address: realAddress);
        _recalculateRouteIfPossible();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[RiderViewModel] reverseGeocode failed: $e');
    }
  }

  void startPinPicker({bool isPickup = true, LocationPoint? initialPoint}) {
    _isPinMode = true;
    _isPinningPickup = isPickup;
    _tempPinLocation = initialPoint ?? (isPickup ? _pickupLocation : _dropoffLocation);
    _deviceService.triggerHaptic('light');
    notifyListeners();
  }

  void cancelPinPicker() {
    _isPinMode = false;
    _tempPinLocation = null;
    _isResolvingPinAddress = false;
    _deviceService.triggerHaptic('light');
    notifyListeners();
  }

  void togglePinMode({bool isPickup = true}) {
    if (_isPinMode) {
      confirmPinLocation();
    } else {
      startPinPicker(isPickup: isPickup);
    }
  }

  int _geocodeRequestId = 0;

  Future<void> updatePinnedCoordinates(double lat, double lng) async {
    final reqId = ++_geocodeRequestId;
    _isResolvingPinAddress = true;
    _tempPinLocation = LocationPoint(
      latitude: lat,
      longitude: lng,
      address: _tempPinLocation?.address ?? 'Pinning location...',
    );
    notifyListeners();

    try {
      final realAddress = await _mapService.reverseGeocode(lat, lng);
      if (_isDisposed || reqId != _geocodeRequestId) return;
      _tempPinLocation = LocationPoint(
        latitude: lat,
        longitude: lng,
        address: realAddress.isNotEmpty
            ? realAddress
            : '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
      );
    } catch (e) {
      debugPrint('[RiderViewModel] reverseGeocode failed: $e');
    } finally {
      if (reqId == _geocodeRequestId) {
        _isResolvingPinAddress = false;
        notifyListeners();
      }
    }
  }

  void confirmPinLocation() {
    final chosen = _tempPinLocation;
    if (chosen != null) {
      if (_isPinningPickup) {
        setPickup(chosen);
      } else {
        setDestination(chosen);
      }
    }
    _isPinMode = false;
    _tempPinLocation = null;
    _isResolvingPinAddress = false;
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  Future<void> setPickup(LocationPoint point) async {
    _pickupLocation = point;
    pickupController.text = point.address;
    _hasPickupFromGps = true;
    notifyListeners();

    if (_dropoffLocation != null) {
      await autoFetchRoute();
    }
  }

  Future<void> setDestination(LocationPoint point) async {
    _dropoffLocation = point;
    dropoffController.text = point.address;
    notifyListeners();

    if (_pickupLocation != null) {
      await autoFetchRoute();
    }
  }

  Future<void> setDropoff(LocationPoint point) async {
    await setDestination(point);
  }

  Future<void> autoFetchRoute() async {
    final pickup = _pickupLocation;
    final dropoff = _dropoffLocation;
    if (pickup == null || dropoff == null) return;

    _routeDebounce?.cancel();
    _isLoadingRoute = true;
    _routeError = null;
    notifyListeners();

    try {
      await _loadRoute(
        LatLng(pickup.latitude, pickup.longitude),
        LatLng(dropoff.latitude, dropoff.longitude),
      );
      await calculateAiSweetSpotBid();
    } catch (e) {
      debugPrint('[RiderViewModel] Auto route fetch error: $e');
    } finally {
      _isLoadingRoute = false;
      notifyListeners();
    }
  }

  Future<void> calculateAiSweetSpotBid() async {
    final sel = selectedRoute;
    if (sel == null || _estimatedDistanceKm <= 0) return;

    try {
      _aiSuggestedSweetSpot = await _pricingMLService.predictSuggestedBid(
        distanceKm: _estimatedDistanceKm,
        trafficMultiplier: _routeTraffic.isNotEmpty ? 1.25 : 1.15,
      );
      if (!_fareTouchedByUser) {
        final fareToUse = _aiSuggestedSweetSpot ?? sel.economics.riderFare;
        fareController.text = fareToUse.round().toString();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[RiderViewModel] AI pricing prediction error: $e');
    }
  }

  void _recalculateRouteIfPossible() {
    autoFetchRoute();
  }

  void selectRoute(int index) {
    if (index == _selectedRouteIndex || index < 0 || index >= _routes.length) {
      return;
    }
    _selectedRouteIndex = index;
    final sel = _routes[index];
    _routePolyline = sel.polylinePoints;
    _routeTraffic = sel.trafficIntervals;
    _estimatedDistanceKm = double.parse(sel.distanceKm.toStringAsFixed(1));
    _estimatedDurationMin = double.parse(sel.durationMin.toStringAsFixed(0));

    _pricingMLService.predictSuggestedBid(
      distanceKm: _estimatedDistanceKm,
      trafficMultiplier: _routeTraffic.isNotEmpty ? 1.25 : 1.15,
    ).then((bid) {
      _aiSuggestedSweetSpot = bid;
      if (!_fareTouchedByUser) {
        fareController.text = bid.round().toString();
      }
      notifyListeners();
    }).catchError((e) {
      debugPrint('[RiderViewModel] AI Pricing ML error on route select: $e');
    });

    if (!_fareTouchedByUser) {
      fareController.text = sel.economics.riderFare.round().toString();
    }
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  @visibleForTesting
  void setTestRoutes(List<RouteOption> routes, {int defaultIndex = 0}) {
    _routeDebounce?.cancel();
    _routeRequestId++;
    _routes = routes;
    _selectedRouteIndex = defaultIndex;
    if (_routes.isNotEmpty && _selectedRouteIndex < _routes.length) {
      final sel = _routes[_selectedRouteIndex];
      _routePolyline = sel.polylinePoints;
      _routeTraffic = sel.trafficIntervals;
      _estimatedDistanceKm = sel.distanceKm;
      _estimatedDurationMin = sel.durationMin;
    }
    notifyListeners();
  }

  Future<void> _loadRoute(LatLng origin, LatLng dest) async {
    _routeError = null;
    final requestId = ++_routeRequestId;

    RoutePlan? plan;
    try {
      plan = await _mapService.fetchRoute(origin, dest);
    } catch (e) {
      debugPrint('[RiderViewModel] route fetch failed: $e');
    }

    if (requestId != _routeRequestId) return;

    if (plan == null || plan.routes.isEmpty) {
      _routes = [];
      _selectedRouteIndex = 0;
      _routePolyline = [];
      _routeTraffic = [];
      _estimatedDistanceKm = 0;
      _estimatedDurationMin = 0;
      _aiSuggestedSweetSpot = null;
      _routeError = 'Could not compute a route. Check your connection.';
      notifyListeners();
      return;
    }

    _routeIsEstimated = false;
    _routes = plan.routes;
    _selectedRouteIndex =
        (plan.defaultIndex >= 0 && plan.defaultIndex < _routes.length)
            ? plan.defaultIndex
            : 0;

    debugPrint('[MAP-DEBUG] routes=${_routes.length} '
        'selected=$_selectedRouteIndex '
        'polylinePoints=${_routes.isNotEmpty ? _routes[_selectedRouteIndex].polylinePoints.length : 0}');

    final sel = selectedRoute;
    if (sel != null) {
      _routePolyline = sel.polylinePoints;
      _routeTraffic = sel.trafficIntervals;
      _estimatedDistanceKm = double.parse(sel.distanceKm.toStringAsFixed(1));
      _estimatedDurationMin = double.parse(sel.durationMin.toStringAsFixed(0));

      try {
        _aiSuggestedSweetSpot = await _pricingMLService.predictSuggestedBid(
          distanceKm: _estimatedDistanceKm,
          trafficMultiplier: _routeTraffic.isNotEmpty ? 1.25 : 1.15,
        );
      } catch (e) {
        debugPrint('[RiderViewModel] AI pricing prediction error: $e');
      }

      if (!_fareTouchedByUser) {
        final fareToUse = _aiSuggestedSweetSpot ?? sel.economics.riderFare;
        fareController.text = fareToUse.round().toString();
      }
    } else {
      _routePolyline = [];
      _routeTraffic = [];
      _estimatedDistanceKm = 0;
      _estimatedDurationMin = 0;
      _aiSuggestedSweetSpot = null;
    }

    notifyListeners();
  }

  void quickIncrementFare(double increment) {
    _fareTouchedByUser = true;
    final cur = double.tryParse(fareController.text) ?? suggestedFare;
    fareController.text = (cur + increment).round().toString();
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  void markFareEditedByUser() {
    _fareTouchedByUser = true;
  }

  bool get routeIsEstimated => _routeIsEstimated;

  void selectPaymentMethod(PaymentRail rail) {
    if (!rail.isConfigured) return;
    _selectedRail = rail;
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  Future<bool> submitRideRequest({
    required RideProvider rideProv,
  }) async {
    final fare = double.tryParse(fareController.text) ?? suggestedFare;
    _deviceService.triggerHaptic('medium');

    final pickup = _pickupLocation;
    final dropoff = _dropoffLocation;
    if (pickup == null || dropoff == null) {
      _deviceService.triggerHaptic('vibrate');
      return false;
    }

    final rideId = await rideProv.requestRide(
      pickup: pickup,
      dropoff: dropoff,
      offeredFare: fare,
      distanceKm: _estimatedDistanceKm,
      durationMin: _estimatedDurationMin,
    );

    if (rideId == null) {
      _deviceService.triggerHaptic('vibrate');
      return false;
    }

    _notificationService.showNotification(
      id: 201,
      title: 'Searching Drivers',
      body: 'Offer sent: PKR ${fare.toInt()} (0% Commission)',
    );
    return true;
  }

  void acceptDriverOffer(RideProvider rideProv, String offerId) {
    _deviceService.triggerHaptic('heavy');
    rideProv.acceptOffer(offerId);

    _notificationService.showNotification(
      id: 202,
      title: 'Driver Confirmed!',
      body: 'Driver is en route to pickup. Safe travels!',
    );
    _audioService.speak('Driver confirmed your ride.');
  }

  Future<SosDispatchResult> dispatchSos({
    required SafetyProvider safetyProv,
    required String rideId,
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    await _safetyService.triggerEmergencyHaptics();
    await _audioService.playAlertTone('siren');
    await _notificationService.showNotification(
      id: 999,
      title: 'EMERGENCY SOS ACTIVE',
      body: 'Broadcasting your live location to your contacts and driver.',
      channelId: 'swiftride_emergency',
    );

    final result = await _safetyEvents.triggerSos(
      rideId: rideId,
      latitude: latitude,
      longitude: longitude,
      message: 'Rider initiated emergency alert',
    );

    safetyProv.triggerSos(
      rideId: rideId,
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      message: result.message,
    );

    return result;
  }

  Future<bool> sendEmergencySms({
    required String recipientPhone,
    required String messageText,
  }) {
    return _safetyService.sendEmergencySms(
      recipientPhone: recipientPhone,
      messageText: messageText,
    );
  }

  Future<bool> callDriver(String phone) async {
    if (phone.trim().isEmpty) return false;
    return await _launcherService.launchDialer(phone);
  }

  Future<bool> callPolice() async {
    return await _launcherService.launchDialer('15');
  }

  Future<String?> generateShareLink({
    required SafetyProvider safetyProv,
    required RideProvider rideProv,
  }) async {
    final ride = rideProv.activeRide;
    if (ride == null) return null;

    final url = await _safetyEvents.createShareLink(ride.id);
    if (url == null) return null;

    final token = Uri.tryParse(url)?.queryParameters['token'];
    if (token != null) rideProv.attachShareToken(token);

    _deviceService.triggerHaptic('light');
    return url;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _routeDebounce?.cancel();
    pickupController.dispose();
    dropoffController.dispose();
    fareController.dispose();
    super.dispose();
  }
}