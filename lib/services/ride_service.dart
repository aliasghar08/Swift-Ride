import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/id_generator.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/ride_offer_model.dart';

/// Ride utilities that are not backed by Firestore.
///
/// The ride lifecycle itself lives in `FirestoreRideService` (Firestore) and the
/// `requestRide` / `acceptOffer` / `updateRideStatus` Cloud Functions.
///
/// This class previously carried a **complete in-memory simulation** of that
/// lifecycle — creating rides locally, fabricating driver offers named
/// "Marcus Vance", and moving a ride through its states without touching the
/// server. That duplicate implementation was the reason the app appeared to work
/// end to end while no ride ever reached a real driver. It has been deleted, and
/// only the two genuinely used operations remain.
class RideService {
  /// Publishes the driver's live position for [activeRideId].
  ///
  /// Routed through the `updateDriverLocation` Cloud Function rather than a
  /// direct Firestore write so the server can verify the caller really is the
  /// assigned driver, and so the fix is mirrored onto the ride document the
  /// rider is already subscribed to.
  Future<void> publishDriverLocation({
    required double latitude,
    required double longitude,
    required String activeRideId,
    double heading = 0.0,
    double speed = 0.0,
  }) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseFunctions.instance.httpsCallable('updateDriverLocation').call({
        'lat': latitude,
        'lng': longitude,
        'heading': heading,
        'speed': speed,
        'activeRideId': activeRideId,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RideService.publishDriverLocation] ${e.code}: ${e.message}');
    } catch (e) {
      debugPrint('[RideService.publishDriverLocation] failed: $e');
    }
  }

  /// Builds the offer a driver submits for [rideId].
  ///
  /// [driverName] is passed in from the signed-in user: this used to be
  /// hardcoded to "Marcus Vance (You)", so every rider saw a bid from a driver
  /// who did not exist.
  RideOffer createDriverCounterOffer({
    required String rideId,
    required DriverProfile driver,
    required String driverName,
    required double counterFare,
    int etaMinutes = 4,
  }) {
    final vehicle = driver.vehicle;
    final summary = [
      vehicle.color,
      vehicle.make,
      vehicle.model,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final plate = vehicle.plate.isEmpty ? '' : ' (${vehicle.plate})';

    return RideOffer(
      id: IdGenerator.generateId(prefix: 'offer_'),
      rideId: rideId,
      driverId: driver.userId,
      driverName: driverName.trim().isEmpty ? 'Your driver' : driverName.trim(),
      counterFare: counterFare,
      etaMinutes: etaMinutes,
      vehicleSummary: summary.isEmpty ? 'Vehicle details unavailable' : '$summary$plate',
      driverRating: driver.rating,
      createdAt: DateTime.now(),
    );
  }
}
