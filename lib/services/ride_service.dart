import '../core/utils/distance_calculator.dart';
import '../core/utils/id_generator.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/location_point_model.dart';
import '../domain/models/ride_model.dart';
import '../domain/models/ride_offer_model.dart';
import '../domain/models/ride_status.dart';

/// Zero-dependency ride service handling fare estimation, bidding negotiation,
/// 4-digit safety PIN verification, and ride state lifecycle transitions.
class RideService {
  /// Estimates suggested fair fare using platform baseline constants.
  double estimateSuggestedFare(double distanceKm, double durationMin) {
    return DistanceCalculator.calculateSuggestedFare(distanceKm, durationMin);
  }

  /// Creates a new ride request with rider proposed fare and 4-digit PIN.
  RideModel createRideRequest({
    required String riderId,
    required LocationPoint pickup,
    required LocationPoint dropoff,
    required double offeredFare,
    required double distanceKm,
    required double durationMin,
  }) {
    final pin = IdGenerator.generatePin();
    final suggested = estimateSuggestedFare(distanceKm, durationMin);

    return RideModel(
      id: IdGenerator.generateId(prefix: 'ride_'),
      riderId: riderId,
      status: RideStatus.requested,
      pickup: pickup,
      dropoff: dropoff,
      offeredFare: offeredFare,
      suggestedFare: suggested,
      distanceKm: distanceKm,
      durationMin: durationMin,
      commissionAmount: 0.0, // 0% commission in Year 1
      pin: pin,
      createdAt: DateTime.now(),
    );
  }

  /// Generates realistic driver counter-offers for inDrive-style negotiation.
  List<RideOffer> generateInitialDriverOffers({
    required RideModel ride,
    required DriverProfile currentDriver,
  }) {
    // Offer 1: Current driver matches rider's offered fare
    final offer1 = RideOffer(
      id: IdGenerator.generateId(prefix: 'offer_'),
      rideId: ride.id,
      driverId: currentDriver.userId,
      driverName: 'Marcus Vance',
      counterFare: ride.offeredFare,
      etaMinutes: 3,
      vehicleSummary: '${currentDriver.vehicle.color} ${currentDriver.vehicle.make} ${currentDriver.vehicle.model} (${currentDriver.vehicle.plate})',
      driverRating: currentDriver.rating,
      createdAt: DateTime.now(),
    );

    // Offer 2: Competing driver submits counter-offer (+$1.50)
    final roundedCounter = ((ride.offeredFare + 1.50) * 2).round() / 2;
    final offer2 = RideOffer(
      id: IdGenerator.generateId(prefix: 'offer_'),
      rideId: ride.id,
      driverId: 'driver_elena_404',
      driverName: 'Elena Rostova',
      counterFare: roundedCounter,
      etaMinutes: 2,
      vehicleSummary: 'Silver Hyundai Ioniq 5 (9ABC332)',
      driverRating: 4.98,
      createdAt: DateTime.now(),
    );

    return [offer1, offer2];
  }

  /// Creates a driver counter-offer.
  RideOffer createDriverCounterOffer({
    required String rideId,
    required DriverProfile driver,
    required double counterFare,
    int etaMinutes = 4,
  }) {
    return RideOffer(
      id: IdGenerator.generateId(prefix: 'offer_'),
      rideId: rideId,
      driverId: driver.userId,
      driverName: 'Marcus Vance (You)',
      counterFare: counterFare,
      etaMinutes: etaMinutes,
      vehicleSummary: '${driver.vehicle.color} ${driver.vehicle.make} ${driver.vehicle.model} (${driver.vehicle.plate})',
      driverRating: driver.rating,
      createdAt: DateTime.now(),
    );
  }

  /// Accepts a driver's offer, locking in the agreed fare and transitioning status.
  RideModel acceptOffer(RideModel ride, RideOffer offer) {
    return ride.copyWith(
      driverId: offer.driverId,
      acceptedFare: offer.counterFare,
      status: RideStatus.accepted,
    );
  }

  /// Transitions ride status to driver arrived at pickup location.
  RideModel markDriverArrived(RideModel ride) {
    return ride.copyWith(status: RideStatus.driverArrived);
  }

  /// Verifies rider's 4-digit PIN before starting the trip.
  /// Returns updated RideModel if PIN matches, otherwise returns null.
  RideModel? verifyPinAndStartTrip(RideModel ride, String enteredPin) {
    if (ride.pin.trim() != enteredPin.trim()) {
      return null;
    }
    return ride.copyWith(status: RideStatus.inProgress);
  }

  /// Marks trip as completed, records completion time, and sets payment to paid.
  RideModel completeTrip(RideModel ride) {
    return ride.copyWith(
      status: RideStatus.completed,
      completedAt: DateTime.now(),
      paymentStatus: 'paid',
    );
  }

  /// Cancels an active ride.
  RideModel cancelRide(RideModel ride, String reason) {
    return ride.copyWith(
      status: RideStatus.cancelled,
      completedAt: DateTime.now(),
      safetyFlags: [...ride.safetyFlags, 'Cancelled: $reason'],
    );
  }
}
