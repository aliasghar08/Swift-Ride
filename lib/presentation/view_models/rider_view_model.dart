import 'package:flutter/material.dart';
import '../../domain/models/location_point_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/safety_provider.dart';
import '../../services/native/native_device_service.dart';
import '../../services/native/native_safety_service.dart';

/// ViewModel managing Rider UI state, fare input, validation,
/// and native device/safety integrations.
class RiderViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final NativeSafetyService _safetyService;

  final TextEditingController pickupController =
      TextEditingController(text: 'Downtown Central Station (700 Market St)');
  final TextEditingController dropoffController =
      TextEditingController(text: 'Financial District Plaza (555 California St)');
  final TextEditingController fareController = TextEditingController(text: '5.50');

  final double estimatedDistanceKm = 4.8;
  final double estimatedDurationMin = 12.0;

  bool _isPinMode = false;
  String _selectedPaymentMethod = 'Credit / Debit Card (Stripe)';

  RiderViewModel({
    NativeDeviceService? deviceService,
    NativeSafetyService? safetyService,
  })  : _deviceService = deviceService ?? NativeDeviceService(),
        _safetyService = safetyService ?? NativeSafetyService();

  bool get isPinMode => _isPinMode;
  String get selectedPaymentMethod => _selectedPaymentMethod;

  double get suggestedFare =>
      ((2.0 + (estimatedDistanceKm * 0.5) + (estimatedDurationMin * 0.1)) * 2).round() / 2;

  void togglePinMode() {
    _isPinMode = !_isPinMode;
    _deviceService.triggerHaptic('light');
    notifyListeners();
  }

  void updatePinnedCoordinates(double lat, double lng) {
    pickupController.text = 'Pinned (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
    notifyListeners();
  }

  void quickIncrementFare(double increment) {
    final cur = double.tryParse(fareController.text) ?? suggestedFare;
    fareController.text = (cur + increment).toStringAsFixed(2);
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

    rideProv.requestRide(
      riderId: authProv.currentUser.id,
      pickup: LocationPoint(
        latitude: 37.7749,
        longitude: -122.4194,
        address: pickupController.text,
      ),
      dropoff: LocationPoint(
        latitude: 37.7850,
        longitude: -122.4060,
        address: dropoffController.text,
      ),
      offeredFare: fare,
      distanceKm: estimatedDistanceKm,
      durationMin: estimatedDurationMin,
      currentDriver: driverProv.driverProfile,
    );
  }

  void acceptDriverOffer(RideProvider rideProv, String offerId) {
    _deviceService.triggerHaptic('heavy');
    rideProv.acceptOffer(offerId);
  }

  Future<void> dispatchSos({
    required SafetyProvider safetyProv,
    required String rideId,
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    // 1. Native emergency broadcast & hardware siren vibration via MethodChannel
    await _safetyService.triggerEmergencyAlert(
      rideId: rideId,
      latitude: latitude,
      longitude: longitude,
      message: 'Rider initiated emergency alert',
    );
    await _safetyService.triggerEmergencyHaptics();

    // 2. Register safety event in state
    safetyProv.triggerSos(
      rideId: rideId,
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      message: 'Rider initiated emergency alert',
    );
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
