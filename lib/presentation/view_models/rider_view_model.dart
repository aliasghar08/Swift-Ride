import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/utils/distance_calculator.dart';
import '../../domain/models/location_point_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/safety_provider.dart';
import '../../services/map_service.dart';
import '../../services/native/native_device_service.dart';
import '../../services/native/native_safety_service.dart';

/// ViewModel managing Rider UI state, address search, pin-dropping,
/// route polylines, PKR fare negotiation, and native safety integrations.
class RiderViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final NativeSafetyService _safetyService;
  final MapService _mapService = MapService();

  final TextEditingController pickupController =
      TextEditingController(text: 'Current Location');
  final TextEditingController dropoffController =
      TextEditingController(text: 'Islamabad International Airport (ISB)');
  final TextEditingController fareController = TextEditingController(text: '450');

  double _estimatedDistanceKm = 8.5;
  double _estimatedDurationMin = 18.0;

  LocationPoint? _pickupLocation;
  LocationPoint? _dropoffLocation;
  List<LatLng> _routePolyline = [];

  bool _isPinMode = false;
  String _selectedPaymentMethod = 'Cash on Dropoff (PKR)';

  RiderViewModel({
    NativeDeviceService? deviceService,
    NativeSafetyService? safetyService,
  })  : _deviceService = deviceService ?? NativeDeviceService(),
        _safetyService = safetyService ?? NativeSafetyService() {
    _initDefaultPKRFare();
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

  void _initDefaultPKRFare() {
    final fare = DistanceCalculator.calculateSuggestedFare(_estimatedDistanceKm, _estimatedDurationMin);
    fareController.text = fare.toInt().toString();
  }

  /// Initializes pickup address from real device coordinates
  Future<void> initializeFromCoordinates(double lat, double lng) async {
    _pickupLocation = LocationPoint(
      latitude: lat,
      longitude: lng,
      address: 'Current Location',
    );
    final realAddress = await _mapService.reverseGeocode(lat, lng);
    pickupController.text = realAddress;
    _pickupLocation = _pickupLocation!.copyWith(address: realAddress);
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
      _estimatedDistanceKm = route.distanceKm;
      _estimatedDurationMin = route.durationMin;

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
