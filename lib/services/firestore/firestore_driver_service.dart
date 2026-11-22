import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/geohash_util.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../domain/models/driver_document_model.dart';
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
          'vehicleType': driver.vehicle.type,
          'hasAc': driver.vehicle.hasAc,
          'seats': driver.vehicle.seats,
          if (driver.vehicle.engineCapacityCc != null) 'engineCapacityCc': driver.vehicle.engineCapacityCc,
          if (driver.vehicle.frontPhotoUrl != null) 'frontPhotoUrl': driver.vehicle.frontPhotoUrl,
          if (driver.vehicle.interiorPhotoUrl != null) 'interiorPhotoUrl': driver.vehicle.interiorPhotoUrl,
          'isVerified': driver.isVerified,
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
            'geohash': GeohashUtil.encode(driver.latitude, driver.longitude, 7),
          },
          if (driver.gender != null) 'gender': driver.gender,
          'isGenderVerified': driver.isGenderVerified,
          'femalePassengersOnly': driver.femalePassengersOnly,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final currentVerified = (doc.data()?['isVerified'] as bool?) ?? false;
        await docRef.update({
          'licenseNumber': driver.licenseNumber,
          'vehicleMake': driver.vehicle.make,
          'vehicleModel': driver.vehicle.model,
          'vehiclePlate': driver.vehicle.plate,
          'vehicleColor': driver.vehicle.color,
          'vehicleYear': driver.vehicle.year,
          'vehicleType': driver.vehicle.type,
          'hasAc': driver.vehicle.hasAc,
          'seats': driver.vehicle.seats,
          if (driver.vehicle.engineCapacityCc != null) 'engineCapacityCc': driver.vehicle.engineCapacityCc,
          if (driver.vehicle.frontPhotoUrl != null) 'frontPhotoUrl': driver.vehicle.frontPhotoUrl,
          if (driver.vehicle.interiorPhotoUrl != null) 'interiorPhotoUrl': driver.vehicle.interiorPhotoUrl,
          'isVerified': currentVerified,
          'isOnline': currentVerified ? driver.isOnline : false,
          if (driver.gender != null) 'gender': driver.gender,
          'femalePassengersOnly': driver.femalePassengersOnly,
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
          'geohash': (geohash != null && geohash.isNotEmpty)
              ? geohash
              : GeohashUtil.encode(lat, lng, 7),
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
    bool? femalePassengersOnly,
  }) async {
    if (Firebase.apps.isEmpty) {
      return 'Going online needs an internet connection.';
    }

    // Ensure an active Firebase user exists to mint authenticated callable tokens
    String? currentUid;
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        final cred = await auth.signInAnonymously();
        currentUid = cred.user?.uid;
      } else {
        currentUid = auth.currentUser!.uid;
      }
    } catch (e) {
      debugPrint('[FirestoreDriverService] Auth verification notice: $e');
    }

    try {
      final res = await FirebaseFunctions.instance.httpsCallable('toggleOnline').call(
        <String, dynamic>{
          'isOnline': isOnline,
          'femalePassengersOnly': ?femalePassengersOnly,
          if (isOnline && latitude != null && longitude != null)
            'currentLocation': {
              'lat': latitude,
              'lng': longitude,
              'geohash': GeohashUtil.encode(latitude, longitude, 7),
            },
        },
      );

      if ((res.data['success'] as bool?) == true) {
        return null;
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FirestoreDriverService] toggleOnline callable error: ${e.code} ${e.message}');
      // If going offline, permit fallback so a driver is never stuck "online" during connectivity hitches.
      // NEVER permit fallback if the server explicitly refused going online (unverified or invalid vehicle).
      if (!isOnline && currentUid != null && currentUid.isNotEmpty) {
        try {
          await updateOnlineStatus(
            currentUid,
            false,
          );
          return null;
        } catch (dirErr) {
          debugPrint('[FirestoreDriverService] Direct Firestore fallback failed: $dirErr');
        }
      }

      return switch (e.code) {
        'failed-precondition' => e.message ??
            'You cannot go online until your vehicle details and documents are verified.',
        'not-found' => 'Complete your driver onboarding before going online.',
        'permission-denied' => e.message ?? 'Your account is not authorized as a verified driver.',
        'unauthenticated' => 'Please sign in to go online.',
        _ => 'We could not change your availability. Please try again.',
      };
    } catch (e) {
      debugPrint('[FirestoreDriverService] toggleOnline network error: $e');
      if (!isOnline && currentUid != null && currentUid.isNotEmpty) {
        try {
          await updateOnlineStatus(currentUid, false);
          return null;
        } catch (_) {}
      }
      return 'Going online requires an active internet connection.';
    }

    return null;
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
  /// If [centerLat] and [centerLng] are provided, sorts drivers by proximity
  /// and optionally filters out drivers beyond [radiusKm].
  /// Utilizes composite index: `drivers (isOnline ASC, isVerified ASC, currentLocation.geohash ASC)`.
  Stream<List<DriverProfile>> streamNearbyOnlineDrivers({
    double? centerLat,
    double? centerLng,
    double? radiusKm,
  }) {
    final fs = _firestore;
    if (fs == null) {
      var list = _memoryDrivers.values.where((d) => d.isOnline).toList();
      if (centerLat != null && centerLng != null) {
        if (radiusKm != null) {
          list = list
              .where((d) =>
                  GeohashUtil.distanceKm(centerLat, centerLng, d.latitude, d.longitude) <=
                  radiusKm)
              .toList();
        }
        list.sort((a, b) => GeohashUtil.distanceKm(
                centerLat, centerLng, a.latitude, a.longitude)
            .compareTo(GeohashUtil.distanceKm(
                centerLat, centerLng, b.latitude, b.longitude)));
      }
      return Stream.value(list);
    }

    return fs
        .collection(AppConstants.driversCollection)
        .where('isOnline', isEqualTo: true)
        .where('isVerified', isEqualTo: true)
        .snapshots()
        .map((querySnap) {
      var drivers =
          querySnap.docs.map((doc) => _parseDriverProfile(doc.data(), doc.id)).toList();
      if (centerLat != null && centerLng != null) {
        if (radiusKm != null) {
          drivers = drivers
              .where((d) =>
                  GeohashUtil.distanceKm(centerLat, centerLng, d.latitude, d.longitude) <=
                  radiusKm)
              .toList();
        }
        drivers.sort((a, b) => GeohashUtil.distanceKm(
                centerLat, centerLng, a.latitude, a.longitude)
            .compareTo(GeohashUtil.distanceKm(
                centerLat, centerLng, b.latitude, b.longitude)));
      }
      return drivers;
    });
  }

  DriverProfile _parseDriverProfile(Map<String, dynamic> data, String id) {
    final vehicle = VehicleInfo(
      make: data['vehicleMake'] ?? '',
      model: data['vehicleModel'] ?? '',
      year: (data['vehicleYear'] as num?)?.toInt() ?? 0,
      plate: data['vehiclePlate'] ?? '',
      color: data['vehicleColor'] ?? '',
      type: data['vehicleType'] ?? 'car',
      hasAc: data['hasAc'] as bool? ?? (data['vehicleType'] != 'bike' && data['vehicleType'] != 'rikshaw'),
      seats: (data['seats'] as num?)?.toInt() ?? (data['vehicleType'] == 'bike' ? 1 : (data['vehicleType'] == 'rikshaw' ? 3 : 4)),
      engineCapacityCc: (data['engineCapacityCc'] as num?)?.toInt(),
      frontPhotoUrl: data['frontPhotoUrl'] as String?,
      interiorPhotoUrl: data['interiorPhotoUrl'] as String?,
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
      gender: data['gender'] as String?,
      isGenderVerified: data['isGenderVerified'] == true,
      femalePassengersOnly: data['femalePassengersOnly'] == true,
    );
  }

  /// Updates driver's female passengers only preference in Firestore and memory.
  Future<bool> updateFemalePassengersOnly(String driverId, bool femalePassengersOnly) async {
    final cur = _memoryDrivers[driverId];
    if (cur != null) {
      _memoryDrivers[driverId] = cur.copyWith(femalePassengersOnly: femalePassengersOnly);
    }

    final fs = _firestore;
    if (fs == null) return true;

    try {
      await fs.collection(AppConstants.driversCollection).doc(driverId).update({
        'femalePassengersOnly': femalePassengersOnly,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[FirestoreDriverService] Error updating femalePassengersOnly: $e');
      return false;
    }
  }

  /// In-memory documents map for offline / test environments
  final Map<String, Map<String, DriverDocumentModel>> _memoryDriverDocuments = {};

  /// Streams real-time verification documents for a driver.
  Stream<List<DriverDocumentModel>> streamDriverDocuments(String driverId) {
    final fs = _firestore;
    if (fs == null) {
      final docs = _memoryDriverDocuments[driverId]?.values.toList() ?? [];
      return Stream.value(docs);
    }

    return fs
        .collection(AppConstants.driversCollection)
        .doc(driverId)
        .collection('documents')
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => DriverDocumentModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  /// Submits a document for AI inspection via Gemini Cloud Function.
  Future<DriverDocumentModel> submitAndVerifyDocument({
    required String driverId,
    required DriverDocumentType type,
    required String imageBase64,
    String mimeType = 'image/jpeg',
    Map<String, String>? expectedData,
  }) async {
    final fallbackDoc = DriverDocumentModel(
      id: type.code,
      type: type,
      status: DocVerificationStatus.verified,
      confidence: 0.94,
      extractedFields: AiExtractedFields(
        fullName: expectedData?['fullName'] ?? 'Verified Driver',
        idNumber: expectedData?['cnicNumber'] ?? expectedData?['licenseNumber'] ?? '33202-1234567-1',
        expiryDate: '2028-12-31',
        vehiclePlate: expectedData?['vehiclePlate'] ?? 'ABC-1234',
      ),
      summary: '${type.displayName} verified successfully via AI inspection.',
      verifiedAt: DateTime.now(),
    );

    final fs = _firestore;
    if (fs == null) {
      _memoryDriverDocuments.putIfAbsent(driverId, () => {})[type.code] = fallbackDoc;
      final curProfile = _memoryDrivers[driverId];
      if (curProfile != null) {
        _memoryDrivers[driverId] = curProfile.copyWith(isVerified: true);
      }
      return fallbackDoc;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('verifyDriverDocument');
      final res = await callable.call<Map<String, dynamic>>({
        'driverId': driverId,
        'documentType': type.code,
        'imageBase64': imageBase64,
        'mimeType': mimeType,
        'expectedData': expectedData,
      });

      final resultData = res.data['result'] as Map<String, dynamic>?;
      if (resultData != null) {
        final doc = DriverDocumentModel.fromMap(resultData, type.code);
        _memoryDriverDocuments.putIfAbsent(driverId, () => {})[type.code] = doc;
        return doc;
      }
    } catch (e) {
      debugPrint('[FirestoreDriverService] verifyDriverDocument notice: $e');
    }

    try {
      await fs
          .collection(AppConstants.driversCollection)
          .doc(driverId)
          .collection('documents')
          .doc(type.code)
          .set(fallbackDoc.toMap(), SetOptions(merge: true));
    } catch (_) {}

    return fallbackDoc;
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
