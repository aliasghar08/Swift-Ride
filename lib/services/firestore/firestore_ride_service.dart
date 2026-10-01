import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_offer_model.dart';
import '../../domain/models/ride_status.dart';

/// Production Firestore service managing the complete lifecycle of rides and driver bidding.
/// Matches Firestore security rules and composite index specifications.
class FirestoreRideService {
  static final FirestoreRideService _instance = FirestoreRideService._internal();
  factory FirestoreRideService() => _instance;
  FirestoreRideService._internal();

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  // In-memory fallback stores for testing/offline environments
  final Map<String, RideModel> _memoryRides = {};
  final Map<String, List<RideOffer>> _memoryOffers = {};

  /// Creates a new ride request in Firestore (`rides/{rideId}`).
  Future<void> createRide(RideModel ride) async {
    _memoryRides[ride.id] = ride;
    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.ridesCollection).doc(ride.id).set({
        'riderId': ride.riderId,
        'driverId': ride.driverId,
        'status': ride.status.toDbString(),
        'pickup': {
          'geopoint': GeoPoint(ride.pickup.latitude, ride.pickup.longitude),
          'address': ride.pickup.address,
          'geohash': ride.pickup.geohash,
        },
        'dropoff': {
          'geopoint': GeoPoint(ride.dropoff.latitude, ride.dropoff.longitude),
          'address': ride.dropoff.address,
          'geohash': ride.dropoff.geohash,
        },
        'offeredFare': ride.offeredFare,
        'acceptedFare': ride.acceptedFare,
        'suggestedFare': ride.suggestedFare,
        'distanceKm': ride.distanceKm,
        'durationMin': ride.durationMin,
        'commissionAmount': ride.commissionAmount,
        'paymentIntentId': ride.paymentIntentId,
        'paymentStatus': ride.paymentStatus,
        'safetyFlags': ride.safetyFlags,
        'shareToken': ride.shareToken,
        'pin': ride.pin,
        'createdAt': FieldValue.serverTimestamp(),
        'completedAt': null,
      });
    } catch (e) {
      debugPrint('[FirestoreRideService] Error creating ride ${ride.id}: $e');
    }
  }

  /// Streams real-time updates for a single ride document.
  Stream<RideModel?> streamRide(String rideId) {
    final fs = _firestore;
    if (fs == null) {
      return Stream.value(_memoryRides[rideId]);
    }

    return fs.collection(AppConstants.ridesCollection).doc(rideId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      final ride = RideModel.fromMap(snap.data()!, docId: snap.id);
      _memoryRides[rideId] = ride;
      return ride;
    });
  }

  /// Fetches a single ride document by [rideId].
  Future<RideModel?> getRide(String rideId) async {
    final fs = _firestore;
    if (fs == null) {
      return _memoryRides[rideId];
    }

    try {
      final doc = await fs.collection(AppConstants.ridesCollection).doc(rideId).get();
      if (doc.exists && doc.data() != null) {
        final ride = RideModel.fromMap(doc.data()!, docId: doc.id);
        _memoryRides[rideId] = ride;
        return ride;
      }
    } catch (e) {
      debugPrint('[FirestoreRideService] Error fetching ride $rideId: $e');
    }
    return _memoryRides[rideId];
  }


  /// Streams active rides for a specific rider.
  /// Utilizes composite index: `rides (riderId ASC, createdAt DESC)`.
  Stream<List<RideModel>> streamRiderActiveRides(String riderId) {
    final fs = _firestore;
    if (fs == null) {
      final list = _memoryRides.values.where((r) => r.riderId == riderId).toList();
      return Stream.value(list);
    }

    return fs
        .collection(AppConstants.ridesCollection)
        .where('riderId', isEqualTo: riderId)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((querySnap) {
      return querySnap.docs.map((doc) => RideModel.fromMap(doc.data(), docId: doc.id)).toList();
    });
  }

  /// Streams requested rides nearby for driver bidding cockpit.
  /// Utilizes composite index: `rides (status ASC, createdAt DESC)`.
  Stream<List<RideModel>> streamAvailableRides() {
    final fs = _firestore;
    if (fs == null) {
      final list = _memoryRides.values.where((r) => r.status == RideStatus.requested).toList();
      return Stream.value(list);
    }

    return fs
        .collection(AppConstants.ridesCollection)
        .where('status', isEqualTo: 'REQUESTED')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((querySnap) {
      return querySnap.docs.map((doc) => RideModel.fromMap(doc.data(), docId: doc.id)).toList();
    });
  }

  /// Submits a driver counter-offer into `ride_offers/{offerId}`.
  Future<void> submitOffer(RideOffer offer) async {
    final list = _memoryOffers.putIfAbsent(offer.rideId, () => []);
    list.add(offer);

    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.rideOffersCollection).doc(offer.id).set({
        'rideId': offer.rideId,
        'driverId': offer.driverId,
        'driverName': offer.driverName,
        'counterFare': offer.counterFare,
        'etaMinutes': offer.etaMinutes,
        'vehicleSummary': offer.vehicleSummary,
        'driverRating': offer.driverRating,
        'status': 'PENDING',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreRideService] Error submitting offer: $e');
    }
  }

  /// Streams incoming driver offers for a ride, sorted by counterFare.
  /// Utilizes composite index: `ride_offers (rideId ASC, status ASC, counterFare ASC)`.
  Stream<List<RideOffer>> streamOffersForRide(String rideId) {
    final fs = _firestore;
    if (fs == null) {
      return Stream.value(_memoryOffers[rideId] ?? []);
    }

    return fs
        .collection(AppConstants.rideOffersCollection)
        .where('rideId', isEqualTo: rideId)
        .where('status', isEqualTo: 'PENDING')
        .orderBy('counterFare', descending: false)
        .snapshots()
        .map((querySnap) {
      return querySnap.docs.map((doc) => RideOffer.fromMap(doc.data(), docId: doc.id)).toList();
    });
  }

  /// Accepts a driver offer and transitions ride status to `ACCEPTED`.
  Future<void> acceptOffer(String rideId, RideOffer offer) async {
    final cur = _memoryRides[rideId];
    if (cur != null) {
      _memoryRides[rideId] = cur.copyWith(
        status: RideStatus.accepted,
        driverId: offer.driverId,
        acceptedFare: offer.counterFare,
      );
    }

    final fs = _firestore;
    if (fs == null) return;

    try {
      final batch = fs.batch();
      final rideRef = fs.collection(AppConstants.ridesCollection).doc(rideId);
      final offerRef = fs.collection(AppConstants.rideOffersCollection).doc(offer.id);

      batch.update(rideRef, {
        'status': 'ACCEPTED',
        'driverId': offer.driverId,
        'acceptedFare': offer.counterFare,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(offerRef, {
        'status': 'ACCEPTED',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      debugPrint('[FirestoreRideService] Error accepting offer: $e');
    }
  }

  /// Signals driver arrival at pickup location.
  Future<void> signalDriverArrival(String rideId) async {
    final cur = _memoryRides[rideId];
    if (cur != null) {
      _memoryRides[rideId] = cur.copyWith(status: RideStatus.driverArrived);
    }

    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.ridesCollection).doc(rideId).update({
        'status': 'DRIVER_ARRIVED',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreRideService] Error signaling arrival: $e');
    }
  }

  /// Convenience alias for signalDriverArrival
  Future<void> markDriverArrived(String rideId) => signalDriverArrival(rideId);

  /// Verifies rider's 4-digit PIN and starts trip.
  Future<bool> verifyPinAndStartTrip(String rideId, String inputPin) async {
    final cur = _memoryRides[rideId];
    if (cur != null && cur.pin == inputPin.trim()) {
      _memoryRides[rideId] = cur.copyWith(status: RideStatus.inProgress);
    }

    final fs = _firestore;
    if (fs == null) {
      return cur?.pin == inputPin.trim();
    }

    try {
      final doc = await fs.collection(AppConstants.ridesCollection).doc(rideId).get();
      if (!doc.exists || doc.data() == null) return false;

      final serverPin = doc.data()!['pin'] as String?;
      if (serverPin == inputPin.trim()) {
        await fs.collection(AppConstants.ridesCollection).doc(rideId).update({
          'status': 'IN_PROGRESS',
          'startedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[FirestoreRideService] Error verifying PIN: $e');
      return false;
    }
  }

  /// Completes trip, settling fare in PKR with 0% commission.
  Future<void> completeTrip(String rideId, {double? finalFare}) async {
    final cur = _memoryRides[rideId];
    final resolvedFare = finalFare ?? cur?.acceptedFare ?? cur?.offeredFare ?? 0.0;
    if (cur != null) {
      _memoryRides[rideId] = cur.copyWith(
        status: RideStatus.completed,
        acceptedFare: resolvedFare,
        completedAt: DateTime.now(),
        paymentStatus: 'paid',
      );
    }

    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.ridesCollection).doc(rideId).update({
        'status': 'COMPLETED',
        'acceptedFare': resolvedFare,
        'paymentStatus': 'paid',
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreRideService] Error completing trip: $e');
    }
  }

  /// Cancels active ride request.
  Future<void> cancelRide(String rideId, String reason) async {
    final cur = _memoryRides[rideId];
    if (cur != null) {
      _memoryRides[rideId] = cur.copyWith(status: RideStatus.cancelled);
    }

    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.ridesCollection).doc(rideId).update({
        'status': 'CANCELLED',
        'cancellationReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreRideService] Error cancelling ride: $e');
    }
  }
}
