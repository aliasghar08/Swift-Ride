import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  /// Parses a ride document defensively.
  ///
  /// Returns null (and logs) instead of throwing when a document is malformed —
  /// a single corrupt record must never tear down a live subscription. It also
  /// avoids the previous behaviour of silently relocating a bad point to a
  /// hardcoded city centre.
  RideModel? _parseRide(Map<String, dynamic> data, String docId) {
    try {
      return RideModel.fromMap(data, docId: docId);
    } catch (e) {
      debugPrint('[FirestoreRideService] Skipping malformed ride $docId: $e');
      return null;
    }
  }

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
        'vehicleType': ride.vehicleType,
        'bookedSeats': ride.bookedSeats,
        'commissionAmount': ride.commissionAmount,
        'paymentIntentId': ride.paymentIntentId,
        'paymentStatus': ride.paymentStatus,
        'paymentMethod': ride.paymentMethod,
        'safetyFlags': ride.safetyFlags,
        'shareToken': ride.shareToken,
        'pin': ride.pin,
        'isAutoNegotiateEnabled': ride.isAutoNegotiateEnabled,
        'maxAutoAcceptFare': ride.maxAutoAcceptFare,
        'cashReceived': ride.cashReceived,
        'changeDue': ride.changeDue,
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
      final ride = _parseRide(snap.data()!, snap.id);
      if (ride != null) _memoryRides[rideId] = ride;
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
        final ride = _parseRide(doc.data()!, doc.id);
        if (ride != null) _memoryRides[rideId] = ride;
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
      return querySnap.docs
          .map((doc) => _parseRide(doc.data(), doc.id))
          .whereType<RideModel>()
          .toList();
    });
  }

  /// Loads recent platform-wide rides for the admin console.
  ///
  /// Admin-gated server-side. The console previously fed its "Live Ride
  /// Activity" panel from the viewing admin's own ride history, so it reported
  /// no activity on a busy platform.
  Future<AdminRidesPage> fetchAdminRides({
    String? status,
    int limit = 50,
  }) async {
    if (Firebase.apps.isEmpty) {
      return const AdminRidesPage(rides: [], error: 'Loading rides needs a connection.');
    }

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('getAdminRides').call(
        <String, dynamic>{
          if (status != null && status != 'ALL') 'status': status,
          'limit': limit,
        },
      );

      final data = res.data as Map<String, dynamic>;
      final raw = (data['rides'] as List<dynamic>?) ?? const [];

      final rides = <RideModel>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final parsed = _parseRide(map, (map['id'] as String?) ?? '');
        if (parsed != null) rides.add(parsed);
      }

      return AdminRidesPage(rides: rides);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreRideService] getAdminRides: ${e.code} ${e.message}');
      return AdminRidesPage(
        rides: const [],
        error: e.code == 'permission-denied'
            ? 'This account is not an administrator.'
            : 'We could not load platform rides.',
      );
    } catch (e) {
      debugPrint('[FirestoreRideService] getAdminRides failed: $e');
      return const AdminRidesPage(rides: [], error: 'We could not load platform rides.');
    }
  }

  /// Records the rider's chosen payment rail on the trip.
  ///
  /// The choice used to live only in the rider's widget state, so the driver had
  /// no idea how they were being paid and the selection vanished on restart.
  /// Returns false when the write failed.
  Future<bool> setPaymentMethod(String rideId, String methodId) async {
    final cached = _memoryRides[rideId];
    if (cached != null) {
      _memoryRides[rideId] = cached.copyWith(paymentMethod: methodId);
    }

    final fs = _firestore;
    if (fs == null) return true;

    try {
      await fs.collection(AppConstants.ridesCollection).doc(rideId).update({
        'paymentMethod': methodId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[FirestoreRideService] setPaymentMethod failed: $e');
      return false;
    }
  }

  /// Asks the backend to record that the driver received cash for [rideId].
  ///
  /// The amount is derived server-side from the ride; only the fact of receipt
  /// is asserted here.
  Future<String?> confirmCashPayment(String rideId) async {
    if (Firebase.apps.isEmpty) {
      return 'Recording a cash payment needs an internet connection.';
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('confirmCashPayment')
          .call(<String, dynamic>{'rideId': rideId});
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreRideService] confirmCashPayment: ${e.code} ${e.message}');
      return e.message ?? 'We could not record the cash payment.';
    } catch (e) {
      debugPrint('[FirestoreRideService] confirmCashPayment failed: $e');
      return 'We could not record the cash payment.';
    }
  }

  /// Finds the user's most recent non-terminal ride, if any.
  ///
  /// Used to restore an in-flight trip after the app is backgrounded or
  /// restarted — without this, a rider or driver who relaunched mid-trip lost
  /// the live ride entirely.
  ///
  /// Queries on `riderId`/`driverId` + `createdAt` (matching the declared
  /// composite indexes) and filters status in memory, so no extra index is
  /// required.
  Future<RideModel?> findActiveRide({
    required String userId,
    required bool asDriver,
  }) async {
    const activeStatuses = {
      RideStatus.requested,
      RideStatus.accepted,
      RideStatus.driverArrived,
      RideStatus.inProgress,
    };

    final fs = _firestore;
    if (fs == null) {
      final candidates = _memoryRides.values
          .where((r) => (asDriver ? r.driverId : r.riderId) == userId)
          .where((r) => activeStatuses.contains(r.status))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return candidates.isEmpty ? null : candidates.first;
    }

    try {
      final snap = await fs
          .collection(AppConstants.ridesCollection)
          .where(asDriver ? 'driverId' : 'riderId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      for (final doc in snap.docs) {
        final ride = _parseRide(doc.data(), doc.id);
        if (ride != null && activeStatuses.contains(ride.status)) return ride;
      }
      return null;
    } catch (e) {
      debugPrint('[FirestoreRideService] findActiveRide failed: $e');
      return null;
    }
  }

  /// Fetches one page of a user's (rider or driver) ride history, newest first.
  /// Supports optional filtering by [asDriver] and [status].
  /// Matches composite indexes:
  /// - `rides (riderId ASC, createdAt DESC)`
  /// - `rides (riderId ASC, status ASC, createdAt DESC)`
  /// - `rides (driverId ASC, createdAt DESC)`
  /// - `rides (driverId ASC, status ASC, createdAt DESC)`
  Future<RideHistoryPage> fetchRideHistoryPage({
    required String riderId,
    bool asDriver = false,
    String? status,
    int limit = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    if (riderId.isEmpty) {
      return const RideHistoryPage(rides: [], hasMore: false);
    }

    final fs = _firestore;
    final userField = asDriver ? 'driverId' : 'riderId';

    if (fs == null) {
      var filtered = _memoryRides.values.where((r) => (asDriver ? r.driverId : r.riderId) == riderId);
      if (status != null && status.isNotEmpty && status != 'ALL') {
        filtered = filtered.where((r) => r.status.toDbString().toUpperCase() == status.toUpperCase());
      }
      final list = filtered.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return RideHistoryPage(rides: list, hasMore: false);
    }

    try {
      Query<Map<String, dynamic>> query = fs
          .collection(AppConstants.ridesCollection)
          .where(userField, isEqualTo: riderId);

      if (status != null && status.isNotEmpty && status != 'ALL') {
        query = query.where('status', isEqualTo: status.toUpperCase());
      }

      query = query.orderBy('createdAt', descending: true).limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snap = await query.get();
      final rides = snap.docs
          .map((doc) => _parseRide(doc.data(), doc.id))
          .whereType<RideModel>()
          .toList();

      return RideHistoryPage(
        rides: rides,
        lastDocument: snap.docs.isNotEmpty ? snap.docs.last : null,
        hasMore: snap.docs.length == limit,
      );
    } catch (e) {
      debugPrint('[FirestoreRideService] ride history page failed: $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('permission-denied') || errStr.contains('unauthenticated')) {
        return const RideHistoryPage(rides: [], hasMore: false);
      }
      return const RideHistoryPage(
        rides: [],
        hasMore: false,
        error: 'We could not load your ride history. Check your connection and try again.',
      );
    }
  }

  /// Explicitly saves or updates a ride document into Firestore trip history.
  /// Captures full location metadata, geohashes, addresses, fares, and timestamps.
  Future<void> saveRideHistory(RideModel ride) async {
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
        'paymentMethod': ride.paymentMethod ?? 'CASH',
        'safetyFlags': ride.safetyFlags,
        'shareToken': ride.shareToken,
        'pin': ride.pin,
        'createdAt': Timestamp.fromDate(ride.createdAt),
        'completedAt': ride.completedAt != null ? Timestamp.fromDate(ride.completedAt!) : null,
        if (ride.driverLocation != null) 'driverLocation': ride.driverLocation!.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also record pickup waypoint in location_history
      await saveLocationHistoryPoint(
        userId: ride.riderId,
        rideId: ride.id,
        latitude: ride.pickup.latitude,
        longitude: ride.pickup.longitude,
        address: ride.pickup.address,
        pointType: 'PICKUP',
      );

      // Record dropoff waypoint if trip reached terminal status
      if (ride.status == RideStatus.completed) {
        await saveLocationHistoryPoint(
          userId: ride.riderId,
          rideId: ride.id,
          latitude: ride.dropoff.latitude,
          longitude: ride.dropoff.longitude,
          address: ride.dropoff.address,
          pointType: 'DROPOFF',
        );
      }
    } catch (e) {
      debugPrint('[FirestoreRideService] saveRideHistory failed: $e');
    }
  }

  /// Records a waypoint or trip breadcrumb in the `location_history` collection.
  /// Indexed by: `location_history (userId ASC, timestamp DESC)` and `(rideId ASC, timestamp ASC)`.
  Future<void> saveLocationHistoryPoint({
    required String userId,
    required String rideId,
    required double latitude,
    required double longitude,
    String? address,
    String pointType = 'WAYPOINT',
  }) async {
    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection('location_history').add({
        'userId': userId,
        'rideId': rideId,
        'pointType': pointType,
        'location': GeoPoint(latitude, longitude),
        'address': address ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirestoreRideService] saveLocationHistoryPoint failed: $e');
    }
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
      return querySnap.docs
          .map((doc) => _parseRide(doc.data(), doc.id))
          .whereType<RideModel>()
          .toList();
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
  ///
  /// Deliberately does NOT mark the ride as paid. Settlement is owned by the
  /// payment flow (payment intent + webhook confirmation); marking a trip paid
  /// here would record money as collected that was never charged.
  Future<void> completeTrip(String rideId, {double? finalFare}) async {
    final cur = _memoryRides[rideId];
    final resolvedFare = finalFare ?? cur?.acceptedFare ?? cur?.offeredFare ?? 0.0;
    if (cur != null) {
      _memoryRides[rideId] = cur.copyWith(
        status: RideStatus.completed,
        acceptedFare: resolvedFare,
        completedAt: DateTime.now(),
      );
    }

    final fs = _firestore;
    if (fs == null) return;

    try {
      await fs.collection(AppConstants.ridesCollection).doc(rideId).update({
        'status': 'COMPLETED',
        'acceptedFare': resolvedFare,
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


/// One page of ride history, plus the cursor needed to fetch the next.
class RideHistoryPage {
  final List<RideModel> rides;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
  final String? error;

  const RideHistoryPage({
    required this.rides,
    this.lastDocument,
    this.hasMore = false,
    this.error,
  });
}


/// One page of platform-wide rides for the admin console.
class AdminRidesPage {
  final List<RideModel> rides;
  final String? error;

  const AdminRidesPage({required this.rides, this.error});
}
