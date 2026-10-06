import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  // Start empty. These used to be pre-filled with a hardcoded Islamabad demo
  // trip ("Blue Area Commercial Center" -> "Islamabad International Airport",
  // PKR 1750, 31.2 km), so the app opened showing a journey the rider never
  // chose and would happily request.
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController fareController = TextEditingController();

  double _estimatedDistanceKm = 0;
  double _estimatedDurationMin = 0;

  LocationPoint? _pickupLocation;
  LocationPoint? _dropoffLocation;
  List<LatLng> _routePolyline = [];
  List<TrafficInterval> _routeTraffic = [];

  Timer? _routeDebounce;
  int _routeRequestId = 0;
  bool _fareTouchedByUser = false;
  bool _routeIsEstimated = false;

  bool _isPinMode = false;
  PaymentRail _selectedRail = PaymentRail.fallback;

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
        _launcherService = launcherService ?? NativeLauncherService() {
    _recalculateRouteIfPossible();
  }

  bool get isPinMode => _isPinMode;
  PaymentRail get selectedRail => _selectedRail;

  /// Label for the selected rail, e.g. "Payment: Cash to Driver".
  String get selectedPaymentMethod => _selectedRail.label;
  double get estimatedDistanceKm => _estimatedDistanceKm;
  double get estimatedDurationMin => _estimatedDurationMin;
  List<LatLng> get routePolyline => _routePolyline;

  /// Per-segment traffic for the current route, for colouring the polyline.
  List<TrafficInterval> get routeTraffic => _routeTraffic;
  LocationPoint? get pickupLocation => _pickupLocation;
  LocationPoint? get dropoffLocation => _dropoffLocation;

  double get suggestedFare =>
      DistanceCalculator.calculateSuggestedFare(_estimatedDistanceKm, _estimatedDurationMin);


  /// Initializes pickup address from real device coordinates
  Future<void> initializeFromCoordinates(double lat, double lng) async {
    // If simulator returns Cupertino / San Francisco coordinates, snap to Islamabad
    final isSimulatorDefault = (lat > 37.0 && lat < 38.0) && (lng < -121.0 && lng > -123.0);
    final targetLat = isSimulatorDefault ? 33.7128 : lat;
    final targetLng = isSimulatorDefault ? 73.0642 : lng;

    _pickupLocation = LocationPoint(
      latitude: targetLat,
      longitude: targetLng,
      address: isSimulatorDefault ? 'Blue Area Commercial Center' : 'Current Location',
    );
    final realAddress = await _mapService.reverseGeocode(targetLat, targetLng);
    pickupController.text = realAddress;
    _pickupLocation = _pickupLocation!.copyWith(address: realAddress);
    _recalculateRouteIfPossible();
    notifyListeners();
  }

  void togglePinMode() {
    _isPinMode = !_isPinMode;
    _deviceService.triggerHaptic('light');
    notifyListeners();
  }

  Future<void> updatePinnedCoordinates(double lat, double lng) async {
    _pickupLocation = LocationPoint(
      latitude: lat,
      longitude: lng,
      address: 'Locating...',
    );
    final realAddress = await _mapService.reverseGeocode(lat, lng);
    pickupController.text = realAddress;
    _pickupLocation = _pickupLocation!.copyWith(address: realAddress);

    _recalculateRouteIfPossible();
    notifyListeners();
  }

  void setPickup(LocationPoint point) {
    _pickupLocation = point;
    pickupController.text = point.address;
    _recalculateRouteIfPossible();
    notifyListeners();
  }

  void setDropoff(LocationPoint point) {
    _dropoffLocation = point;
    dropoffController.text = point.address;
    _recalculateRouteIfPossible();
    notifyListeners();
  }

  /// Debounced route lookup.
  ///
  /// This used to recompute a synthetic polyline synchronously on every
  /// keystroke and overwrite whatever fare the rider had typed.
  void _recalculateRouteIfPossible() {
    final pickup = _pickupLocation;
    final dropoff = _dropoffLocation;
    if (pickup == null || dropoff == null) return;

    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadRoute(
        LatLng(pickup.latitude, pickup.longitude),
        LatLng(dropoff.latitude, dropoff.longitude),
      );
    });
  }

  Future<void> _loadRoute(LatLng origin, LatLng dest) async {
    final requestId = ++_routeRequestId;

    RouteDetails? route;
    try {
      route = await _mapService.fetchRoute(origin, dest);
    } catch (e) {
      debugPrint('[RiderViewModel] route fetch failed: $e');
    }

    // Drop out-of-order responses from a superseded lookup.
    if (requestId != _routeRequestId) return;

    // Fall back to an explicitly-flagged straight-line estimate, never invented
    // "road" geometry.
    route ??= _mapService.estimateStraightLineRoute(origin, dest);

    _routePolyline = route.polylinePoints;
    _routeTraffic = route.trafficIntervals;
    _routeIsEstimated = route.isEstimated;
    _estimatedDistanceKm = double.parse(route.distanceKm.toStringAsFixed(1));
    _estimatedDurationMin = double.parse(route.durationMin.toStringAsFixed(0));

    // Only auto-fill the fare while the rider has not set it themselves.
    if (!_fareTouchedByUser) {
      fareController.text = suggestedFare.toInt().toString();
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

  /// Call when the rider types their own fare, so route recalculation stops
  /// overwriting it.
  void markFareEditedByUser() {
    _fareTouchedByUser = true;
  }

  /// True when the drawn route is a straight-line estimate rather than real road
  /// geometry.
  bool get routeIsEstimated => _routeIsEstimated;

  void selectPaymentMethod(PaymentRail rail) {
    // Unconfigured rails are not selectable, so the rider is never told a card
    // payment is set up when no provider is connected.
    if (!rail.isConfigured) return;
    _selectedRail = rail;
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  /// Submits the ride request to the backend.
  ///
  /// Returns true when the server actually created the ride. Nothing is
  /// fabricated locally: the ride id, PIN and suggested fare all come from the
  /// server.
  Future<bool> submitRideRequest({
    required RideProvider rideProv,
  }) async {
    final fare = double.tryParse(fareController.text) ?? suggestedFare;
    _deviceService.triggerHaptic('medium');

    // Never invent a pickup or dropoff. These previously defaulted to hardcoded
    // Islamabad coordinates, silently matching riders to trips they never chose.
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

  /// Dispatches an emergency alert and returns what actually happened.
  ///
  /// Local siren, haptics and the on-device notification fire first so they work
  /// without connectivity. The remote fan-out then reports honestly whether any
  /// contact or the driver was actually reached — the caller must not claim help
  /// is on the way when [SosDispatchResult.reachedAnyone] is false.
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

    // Server-side fan-out: FCM to the trip counterparty and trusted contacts.
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

  /// Opens the SMS composer addressed to [recipientPhone].
  ///
  /// Returns true only when the composer was presented — the user still has to
  /// send it, so callers must not claim a message was delivered.
  Future<bool> sendEmergencySms({
    required String recipientPhone,
    required String messageText,
  }) {
    return _safetyService.sendEmergencySms(
      recipientPhone: recipientPhone,
      messageText: messageText,
    );
  }

  /// Calls the driver via the native phone dialer.
  ///
  /// [phone] is required: this used to default to a hardcoded
  /// '+92 300 9876543' belonging to nobody, so tapping "Call Driver" always
  /// dialled a stranger.
  Future<bool> callDriver(String phone) async {
    if (phone.trim().isEmpty) return false;
    return await _launcherService.launchDialer(phone);
  }

  /// Calls emergency police (15 in Pakistan) via native phone dialer
  Future<bool> callPolice() async {
    return await _launcherService.launchDialer('15');
  }

  /// Creates a public tracking link for the active trip.
  ///
  /// Returns null when the link could not be created — the caller must say so
  /// rather than presenting a link that will not work. This previously invented
  /// a token on-device, so every shared link resolved to "invalid or expired"
  /// because the server had never heard of it.
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
    _routeDebounce?.cancel();
    pickupController.dispose();
    dropoffController.dispose();
    fareController.dispose();
    super.dispose();
  }
}
