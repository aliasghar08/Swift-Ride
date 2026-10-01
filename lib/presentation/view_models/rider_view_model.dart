import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/utils/distance_calculator.dart';
import '../../domain/models/location_point_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/safety_provider.dart';
import '../../services/map_service.dart';
import '../../services/native/native_audio_service.dart';
import '../../services/native/native_device_service.dart';
import '../../services/native/native_launcher_service.dart';
import '../../services/native/native_notification_service.dart';
import '../../services/native/native_safety_service.dart';

/// ViewModel managing Rider UI state, address search, pin-dropping,
/// route polylines, PKR fare negotiation, and native safety integrations.
class RiderViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final NativeSafetyService _safetyService;
  final NativeNotificationService _notificationService;
  final NativeAudioService _audioService;
  final NativeLauncherService _launcherService;
  final MapService _mapService = MapService();

  final TextEditingController pickupController =
      TextEditingController(text: 'Blue Area Commercial Center');
  final TextEditingController dropoffController =
      TextEditingController(text: 'Islamabad International Airport (ISB)');
  final TextEditingController fareController = TextEditingController(text: '1750');

  double _estimatedDistanceKm = 31.2;
  double _estimatedDurationMin = 37.0;

  LocationPoint? _pickupLocation = const LocationPoint(
    latitude: 33.7128,
    longitude: 73.0642,
    address: 'Blue Area Commercial Center, Islamabad',
  );
  LocationPoint? _dropoffLocation = const LocationPoint(
    latitude: 33.5605,
    longitude: 72.8518,
    address: 'Islamabad International Airport (ISB)',
  );
  List<LatLng> _routePolyline = [];

  bool _isPinMode = false;
  String _selectedPaymentMethod = 'Cash on Dropoff (PKR)';

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
  String get selectedPaymentMethod => _selectedPaymentMethod;
  double get estimatedDistanceKm => _estimatedDistanceKm;
  double get estimatedDurationMin => _estimatedDurationMin;
  List<LatLng> get routePolyline => _routePolyline;
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

  void _recalculateRouteIfPossible() {
    if (_pickupLocation != null && _dropoffLocation != null) {
      final origin = LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude);
      final dest = LatLng(_dropoffLocation!.latitude, _dropoffLocation!.longitude);
      final route = _mapService.calculateRoute(origin, dest);

      _routePolyline = route.polylinePoints;
      _estimatedDistanceKm = double.parse(route.distanceKm.toStringAsFixed(1));
      _estimatedDurationMin = double.parse(route.durationMin.toStringAsFixed(0));

      final suggested = DistanceCalculator.calculateSuggestedFare(_estimatedDistanceKm, _estimatedDurationMin);
      fareController.text = suggested.toInt().toString();
    }
  }

  void quickIncrementFare(double increment) {
    final cur = double.tryParse(fareController.text) ?? suggestedFare;
    fareController.text = (cur + increment).round().toString();
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  void selectPaymentMethod(String method) {
    _selectedPaymentMethod = method;
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  void submitRideRequest({
    required RideProvider rideProv,
    required AuthProvider authProv,
    required DriverProvider driverProv,
  }) {
    final fare = double.tryParse(fareController.text) ?? suggestedFare;
    _deviceService.triggerHaptic('medium');

    final pickup = _pickupLocation ??
        LocationPoint(
          latitude: 33.7128,
          longitude: 73.0642,
          address: pickupController.text,
        );

    final dropoff = _dropoffLocation ??
        LocationPoint(
          latitude: 33.5605,
          longitude: 72.8518,
          address: dropoffController.text,
        );

    rideProv.requestRide(
      riderId: authProv.currentUser.id,
      pickup: pickup,
      dropoff: dropoff,
      offeredFare: fare,
      distanceKm: _estimatedDistanceKm,
      durationMin: _estimatedDurationMin,
      currentDriver: driverProv.driverProfile,
    );

    // Native notification
    _notificationService.showNotification(
      id: 201,
      title: 'Searching Drivers',
      body: 'Offer sent: PKR ${fare.toInt()} (0% Commission)',
    );
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

  Future<void> dispatchSos({
    required SafetyProvider safetyProv,
    required String rideId,
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    // 1. Native emergency broadcast, loud alert tone & hardware siren vibration via MethodChannel
    await _safetyService.triggerEmergencyAlert(
      rideId: rideId,
      latitude: latitude,
      longitude: longitude,
      message: 'Rider initiated emergency alert',
    );
    await _safetyService.triggerEmergencyHaptics();
    await _audioService.playAlertTone('siren');
    await _notificationService.showNotification(
      id: 999,
      title: 'EMERGENCY SOS ACTIVE',
      body: 'Your live GPS location is being broadcast to emergency contacts.',
      channelId: 'swiftride_emergency',
    );

    // 2. Register safety event in state
    safetyProv.triggerSos(
      rideId: rideId,
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      message: 'Rider initiated emergency alert',
    );
  }

  /// Calls the driver via native phone dialer (replaces url_launcher)
  Future<bool> callDriver([String phone = '+92 300 9876543']) async {
    return await _launcherService.launchDialer(phone);
  }

  /// Calls emergency police (15 in Pakistan) via native phone dialer
  Future<bool> callPolice() async {
    return await _launcherService.launchDialer('15');
  }

  String generateShareLink({
    required SafetyProvider safetyProv,
    required RideProvider rideProv,
  }) {
    final token = safetyProv.generateShareToken();
    rideProv.attachShareToken(token);
    _deviceService.triggerHaptic('light');
    return 'https://swiftride.app/track?token=$token';
  }

  @override
  void dispose() {
    pickupController.dispose();
    dropoffController.dispose();
    fareController.dispose();
    super.dispose();
  }
}
