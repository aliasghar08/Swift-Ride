import 'package:flutter/foundation.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/location_point_model.dart';
import '../domain/models/ride_model.dart';
import '../domain/models/ride_offer_model.dart';
import '../services/ride_service.dart';

/// Zero-dependency Ride Provider managing the full ride-hailing lifecycle:
/// fare bidding, inDrive-style negotiation, 4-digit PIN verification, and history.
class RideProvider extends ChangeNotifier {
  final RideService _rideService;
  RideModel? _currentRide;
  List<RideOffer> _activeOffers = [];
  List<RideModel> _rideHistory = [];

  RideProvider({
    RideService? rideService,
    RideModel? initialRide,
    List<RideModel>? initialHistory,
  })  : _rideService = rideService ?? RideService(),
        _currentRide = initialRide,
        _rideHistory = initialHistory ?? [];

  RideModel? get currentRide => _currentRide;
  RideModel? get activeRide => _currentRide;
  List<RideOffer> get activeOffers => List.unmodifiable(_activeOffers);
  List<RideModel> get rideHistory => List.unmodifiable(_rideHistory);

  /// Requests a ride with rider-proposed fare and generates simulated driver counter offers.
  void requestRide({
    required String riderId,
    required LocationPoint pickup,
    required LocationPoint dropoff,
    required double offeredFare,
    required double distanceKm,
    required double durationMin,
    required DriverProfile currentDriver,
  }) {
    final ride = _rideService.createRideRequest(
      riderId: riderId,
      pickup: pickup,
      dropoff: dropoff,
      offeredFare: offeredFare,
      distanceKm: distanceKm,
      durationMin: durationMin,
    );

    final offers = _rideService.generateInitialDriverOffers(
      ride: ride,
      currentDriver: currentDriver,
    );

    _currentRide = ride;
    _activeOffers = offers;
    notifyListeners();
  }

  /// Driver submits an inDrive-style counter offer.
  void submitDriverCounterOffer({
    required String rideId,
    required DriverProfile driver,
    required double counterFare,
  }) {
    final offer = _rideService.createDriverCounterOffer(
      rideId: rideId,
      driver: driver,
      counterFare: counterFare,
    );
    _activeOffers = [..._activeOffers, offer];
    notifyListeners();
  }

  /// Rider accepts a specific driver offer.
  void acceptOffer(String offerId) {
    if (_currentRide == null) return;
    final offer = _activeOffers.firstWhere((o) => o.id == offerId);

    _currentRide = _rideService.acceptOffer(_currentRide!, offer);
    _activeOffers = [];
    notifyListeners();
  }

  /// Driver signals arrival at pickup.
  void driverArrived() {
    if (_currentRide == null) return;
    _currentRide = _rideService.markDriverArrived(_currentRide!);
    notifyListeners();
  }

  /// Verifies 4-digit PIN to begin trip. Returns true if valid, false if invalid.
  bool startTripWithPin(String enteredPin) {
    if (_currentRide == null) return false;
    final updated = _rideService.verifyPinAndStartTrip(_currentRide!, enteredPin);
    if (updated == null) return false;

    _currentRide = updated;
    notifyListeners();
    return true;
  }

  /// Completes trip, moves it to ride history, and clears active ride.
  RideModel? completeTrip() {
    if (_currentRide == null) return null;
    final completed = _rideService.completeTrip(_currentRide!);

    _rideHistory = [completed, ..._rideHistory];
    _currentRide = null;
    _activeOffers = [];
    notifyListeners();
    return completed;
  }

  /// Cancels active ride.
  void cancelRide(String reason) {
    if (_currentRide == null) return;
    final cancelled = _rideService.cancelRide(_currentRide!, reason);

    _rideHistory = [cancelled, ..._rideHistory];
    _currentRide = null;
    _activeOffers = [];
    notifyListeners();
  }

  /// Attaches a generated share token to the current active ride.
  void attachShareToken(String token) {
    if (_currentRide == null) return;
    _currentRide = _currentRide!.copyWith(shareToken: token);
    notifyListeners();
  }
}
