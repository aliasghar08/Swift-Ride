import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
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
