import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/utils/distance_calculator.dart';
import '../core/utils/id_generator.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/location_point_model.dart';
import '../domain/models/ride_model.dart';
import '../domain/models/ride_offer_model.dart';
import '../domain/models/ride_status.dart';

class RouteEstimate {
  final int distanceMeters;
  final int durationSeconds;
  final String polylineEncoded;

  const RouteEstimate({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polylineEncoded,
  });

  double get distanceKm => distanceMeters / 1000.0;
  double get durationMin => durationSeconds / 60.0;
}

/// Zero-dependency ride service handling fare estimation, bidding negotiation,
/// 4-digit safety PIN verification, and ride state lifecycle transitions.
class RideService {
  /// Calls getRoute Cloud Function or falls back to geodesic driving distance.
  Future<RouteEstimate> estimateRoute({
    required LatLng pickup,
    required LatLng dropoff,
  }) async {
    try {
      if (Firebase.apps.isNotEmpty) {
        final callable = FirebaseFunctions.instance.httpsCallable('getRoute');
        final result = await callable.call({
          'origin': {'lat': pickup.latitude, 'lng': pickup.longitude},
          'destination': {'lat': dropoff.latitude, 'lng': dropoff.longitude},
        });
        return RouteEstimate(
          distanceMeters: (result.data['distanceMeters'] as num?)?.toInt() ?? 5000,
          durationSeconds: (result.data['durationSeconds'] as num?)?.toInt() ?? 600,
          polylineEncoded: (result.data['polyline'] as String?) ?? '',
        );
      }
    } catch (e) {
      debugPrint('[RideService.estimateRoute] Fallback to driving distance: $e');
    }

    final distanceKm = DistanceCalculator.estimatedDrivingDistance(
      pickup.latitude,
      pickup.longitude,
      dropoff.latitude,
      dropoff.longitude,
    );
    final durationMin = DistanceCalculator.estimatedDurationMinutes(distanceKm);
    return RouteEstimate(
      distanceMeters: (distanceKm * 1000).toInt(),
      durationSeconds: (durationMin * 60).toInt(),
      polylineEncoded: '',
    );
  }

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

    // Offer 2: Competing driver submits counter-offer (+PKR 50)
    final roundedCounter = (ride.offeredFare + 50.0).roundToDouble();
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
