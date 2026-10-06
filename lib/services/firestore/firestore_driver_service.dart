import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../domain/models/vehicle_info_model.dart';

/// Service managing driver profiles, verification state, and live online telemetry in Firestore.
/// Matches Firestore security rules and composite index `drivers (isOnline ASC, isVerified ASC, currentLocation.geohash ASC)`.
class FirestoreDriverService {
  static final FirestoreDriverService _instance = FirestoreDriverService._internal();
  factory FirestoreDriverService() => _instance;
  FirestoreDriverService._internal();

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  final Map<String, DriverProfile> _memoryDrivers = {};

  /// Saves or updates a driver profile in `drivers/{driverId}`.
  Future<void> saveDriverProfile(DriverProfile driver) async {
    _memoryDrivers[driver.userId] = driver;
    final fs = _firestore;
    if (fs == null) return;

    try {
      final docRef = fs.collection(AppConstants.driversCollection).doc(driver.userId);
      final doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set({
          'userId': driver.userId,
          'licenseNumber': driver.licenseNumber,
          'vehicleMake': driver.vehicle.make,
          'vehicleModel': driver.vehicle.model,
          'vehiclePlate': driver.vehicle.plate,
          'vehicleColor': driver.vehicle.color,
          'vehicleYear': driver.vehicle.year,
          'isVerified': false, // Verification managed by admin/cloud functions
          'isOnline': driver.isOnline,
          'subscriptionStatus': driver.subscriptionStatus.name.toUpperCase(),
          'subscriptionExpiresAt': Timestamp.fromDate(driver.subscriptionExpiresAt),
          'stripeAccountId': driver.stripeAccountId,
          'payoutStatus': driver.payoutStatus,
          'rating': driver.rating,
          'totalRides': driver.totalRides,
          'totalEarnings': driver.totalEarnings,
          'currentLocation': {
            'geopoint': GeoPoint(driver.latitude, driver.longitude),
            'geohash': 'sv8wr', // Default Islamabad geohash
          },
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.update({
          'licenseNumber': driver.licenseNumber,
          'vehicleMake': driver.vehicle.make,
          'vehicleModel': driver.vehicle.model,
          'vehiclePlate': driver.vehicle.plate,
          'vehicleColor': driver.vehicle.color,
          'isOnline': driver.isOnline,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('[FirestoreDriverService] Error saving driver ${driver.userId}: $e');
    }
  }

  /// Fetches a driver profile document by [driverId].
  Future<DriverProfile?> getDriverProfile(String driverId) async {
    final fs = _firestore;
    if (fs == null) {
      return _memoryDrivers[driverId];
    }

    try {
      final doc = await fs.collection(AppConstants.driversCollection).doc(driverId).get();
      if (doc.exists && doc.data() != null) {
        final profile = _parseDriverProfile(doc.data()!, doc.id);
        _memoryDrivers[driverId] = profile;
        return profile;
      }
    } catch (e) {
      debugPrint('[FirestoreDriverService] Error getting driver $driverId: $e');
    }
    return _memoryDrivers[driverId];
  }

  /// Streams real-time updates for a single driver profile.
  Stream<DriverProfile?> streamDriverProfile(String driverId) {
    final fs = _firestore;
    if (fs == null) {
      return Stream.value(_memoryDrivers[driverId]);
    }

    return fs.collection(AppConstants.driversCollection).doc(driverId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      final profile = _parseDriverProfile(doc.data()!, doc.id);
      _memoryDrivers[driverId] = profile;
      return profile;
    });
  }

  /// Updates driver's online status and live GPS location.
  Future<void> updateOnlineStatus(
    String driverId,
    bool isOnline, {
    double? lat,
    double? lng,
    String? geohash,
  }) async {
    final cur = _memoryDrivers[driverId];
    if (cur != null) {
      _memoryDrivers[driverId] = cur.copyWith(
        isOnline: isOnline,
        latitude: lat ?? cur.latitude,
        longitude: lng ?? cur.longitude,
      );
    }

    final fs = _firestore;
    if (fs == null) return;

    try {
      final updates = <String, dynamic>{
        'isOnline': isOnline,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (lat != null && lng != null) {
        updates['currentLocation'] = {
          'geopoint': GeoPoint(lat, lng),
          'geohash': geohash ?? 'sv8wr',
        };
      }

      await fs.collection(AppConstants.driversCollection).doc(driverId).update(updates);
    } catch (e) {
      debugPrint('[FirestoreDriverService] Error updating online status: $e');
    }
  }

  /// Updates driver's live GPS coordinates.
  Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
    String? geohash,
  }) async {
    final cur = _memoryDrivers[driverId];
    await updateOnlineStatus(
      driverId,
      cur?.isOnline ?? true,
      lat: latitude,
      lng: longitude,
      geohash: geohash,
    );
  }


  /// Requests a driver payout through the `requestPayout` Cloud Function.
  ///
  /// Server-side this validates the balance, applies the caller's idempotency
  /// key, and writes the `payouts` ledger. A rail that is not configured reports
  /// a failure rather than a synthetic success.
  Future<PayoutRequestResult> requestPayout({
    required double amount,
    required String rail,
    required String destination,
    required String idempotencyKey,
  }) async {
    if (Firebase.apps.isEmpty) {
      return const PayoutRequestResult.failed(
        'Payouts need an internet connection. Your balance is unchanged.',
      );
    }

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('requestPayout').call(
        <String, dynamic>{
          'amount': amount,
          'rail': rail,
          'destination': destination,
          'idempotencyKey': idempotencyKey,
        },
      );

      final data = res.data as Map<String, dynamic>;
      return PayoutRequestResult(
        accepted: (data['success'] as bool?) ?? false,
        payoutId: data['payoutId'] as String?,
        status: (data['status'] as String?) ?? 'unknown',
        message: (data['message'] as String?) ?? 'Payout submitted.',
        configurationMissing: (data['configurationMissing'] as bool?) ?? false,
        replayed: (data['replayed'] as bool?) ?? false,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreDriverService] requestPayout failed: ${e.code} ${e.message}');
      // `failed-precondition` carries the server's balance guidance.
      return PayoutRequestResult.failed(
        e.code == 'failed-precondition' && e.message != null
            ? e.message!
            : 'We could not start your payout. Your balance is unchanged.',
      );
    } catch (e) {
      debugPrint('[FirestoreDriverService] requestPayout failed: $e');
      return const PayoutRequestResult.failed(
        'We could not start your payout. Your balance is unchanged.',
      );
    }
  }

  /// Sets this driver's availability through the `toggleOnline` Cloud Function.
  ///
  /// Persisting here — rather than flipping a local flag — is what lets the
  /// `onRideCreated` trigger find available drivers. That trigger queries
  /// `drivers where isOnline == true` by geohash, so while this was local-only
  /// it matched zero drivers and ride-request push notifications never fired.
  ///
  /// Returns a message on refusal (e.g. an unverified driver), or null on success.
  Future<String?> setOnline({
    required bool isOnline,
    double? latitude,
    double? longitude,
  }) async {
    if (Firebase.apps.isEmpty) {
      return 'Going online needs an internet connection.';
    }

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('toggleOnline').call(
        <String, dynamic>{
          'isOnline': isOnline,
          if (isOnline && latitude != null && longitude != null)
            'currentLocation': {
              'lat': latitude,
              'lng': longitude,
              'geohash': GeohashUtil.encode(latitude, longitude, 7),
            },
        },
      );

      return (res.data['success'] as bool?) == true
          ? null
          : 'We could not change your availability. Please try again.';
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreDriverService] toggleOnline failed: ${e.code} ${e.message}');
      return switch (e.code) {
        'failed-precondition' => e.message ??
            'You cannot go online until your documents are verified.',
        'not-found' => 'Complete your driver onboarding before going online.',
        'permission-denied' => 'Your account is not set up as a driver.',
        _ => 'We could not change your availability. Please try again.',
      };
    } catch (e) {
      debugPrint('[FirestoreDriverService] toggleOnline failed: $e');
      return 'We could not change your availability. Please try again.';
    }
  }

  /// Fetches this driver's real earnings and withdrawable balance.
  ///
  /// The balance accounts for money already committed to payouts, so the figure
  /// shown in the cockpit matches what `requestPayout` will actually allow.
  Future<DriverEarnings?> fetchEarnings() async {
    if (Firebase.apps.isEmpty) return null;

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('getEarnings').call();
      final data = res.data as Map<String, dynamic>;

      double asDouble(String key) => (data[key] as num?)?.toDouble() ?? 0;
      int asInt(String key) => (data[key] as num?)?.toInt() ?? 0;

      return DriverEarnings(
        totalEarnings: asDouble('totalEarnings'),
        todayEarnings: asDouble('todayEarnings'),
        availablePayoutBalance: asDouble('availablePayoutBalance'),
        committedPayouts: asDouble('committedPayouts'),
        paidOut: asDouble('paidOut'),
        totalCompletedRides: asInt('totalCompletedRides'),
        commissionDeducted: asDouble('commissionDeducted'),
        standardCommissionSaved: asDouble('standardCommissionSaved'),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreDriverService] getEarnings failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[FirestoreDriverService] getEarnings failed: $e');
      return null;
    }
  }

  /// Streams driver applications awaiting verification, for the admin queue.
  ///
  /// The admin dashboard previously rendered a fabricated applicant with no
  /// Firestore backing at all.
  Stream<List<DriverProfile>> streamPendingDrivers() {
    final fs = _firestore;
    if (fs == null) {
      return Stream.value(const <DriverProfile>[]);
    }

    return fs
        .collection(AppConstants.driversCollection)
        .where('isVerified', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => _parseDriverProfile(doc.data(), doc.id))
            .toList());
  }

  /// Streams online and verified drivers.
  /// Utilizes composite index: `drivers (isOnline ASC, isVerified ASC, currentLocation.geohash ASC)`.
  Stream<List<DriverProfile>> streamNearbyOnlineDrivers() {
    final fs = _firestore;
    if (fs == null) {
      return Stream.value(_memoryDrivers.values.where((d) => d.isOnline).toList());
    }

    return fs
        .collection(AppConstants.driversCollection)
        .where('isOnline', isEqualTo: true)
        .where('isVerified', isEqualTo: true)
        .snapshots()
        .map((querySnap) {
      return querySnap.docs.map((doc) => _parseDriverProfile(doc.data(), doc.id)).toList();
    });
  }

  DriverProfile _parseDriverProfile(Map<String, dynamic> data, String id) {
    final vehicle = VehicleInfo(
      make: data['vehicleMake'] ?? 'Toyota',
      model: data['vehicleModel'] ?? 'Camry',
      year: (data['vehicleYear'] as num?)?.toInt() ?? 2022,
      plate: data['vehiclePlate'] ?? 'ABC-1234',
      color: data['vehicleColor'] ?? 'Midnight Black',
    );

    double lat = 33.6844;
    double lng = 73.0479;
    if (data['currentLocation'] is Map) {
      final geo = data['currentLocation']['geopoint'];
      if (geo is GeoPoint) {
        lat = geo.latitude;
        lng = geo.longitude;
      }
    }

    return DriverProfile(
      userId: id,
      licenseNumber: data['licenseNumber'] ?? '',
      vehicle: vehicle,
      isVerified: data['isVerified'] ?? false,
      isOnline: data['isOnline'] ?? false,
      stripeAccountId: data['stripeAccountId'],
      payoutStatus: data['payoutStatus'] ?? 'pending',
      rating: (data['rating'] as num?)?.toDouble() ?? 4.9,
      totalRides: (data['totalRides'] as num?)?.toInt() ?? 0,
      totalEarnings: (data['totalEarnings'] as num?)?.toDouble() ?? 0.0,
      latitude: lat,
      longitude: lng,
      subscriptionExpiresAt: DateTime.now().add(const Duration(days: 365)),
      createdAt: DateTime.now(),
    );
  }
}


/// Outcome of a payout request, as reported by the `requestPayout` function.
class PayoutRequestResult {
  final bool accepted;
  final String? payoutId;
  final String status;
  final String message;
  final bool configurationMissing;
  final bool replayed;

  const PayoutRequestResult({
    required this.accepted,
    required this.status,
    required this.message,
    this.payoutId,
    this.configurationMissing = false,
    this.replayed = false,
  });

  const PayoutRequestResult.failed(String reason)
      : accepted = false,
        payoutId = null,
        status = 'failed',
        message = reason,
        configurationMissing = false,
        replayed = false;
}


/// A driver's earnings and withdrawable balance, as reported by `getEarnings`.
class DriverEarnings {
  final double totalEarnings;
  final double todayEarnings;

  /// What the driver can actually withdraw right now: total earnings minus
  /// everything already committed to a payout.
  final double availablePayoutBalance;
  final double committedPayouts;
  final double paidOut;
  final int totalCompletedRides;
  final double commissionDeducted;
  final double standardCommissionSaved;

  const DriverEarnings({
    required this.totalEarnings,
    required this.todayEarnings,
    required this.availablePayoutBalance,
    required this.committedPayouts,
    required this.paidOut,
    required this.totalCompletedRides,
    required this.commissionDeducted,
    required this.standardCommissionSaved,
  });
}
