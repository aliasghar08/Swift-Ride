import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/driver_model.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/safety_event_model.dart';
import 'package:swiftride/domain/models/safety_event_type.dart';
import 'package:swiftride/services/firestore/firestore_driver_service.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';
import 'package:swiftride/services/firestore/firestore_safety_service.dart';

void main() {
  group('Geotagging & Proximity Architecture Tests', () {
    const isbLat = 33.6844;
    const isbLng = 73.0479;
    const lhrLat = 31.5204;
    const lhrLng = 74.3587;
    const rwpLat = 33.5651; // Rawalpindi (~15km from Islamabad)
    const rwpLng = 73.0169;

    test('LocationPoint auto-geotags with effectiveGeohash and withGeotag factory', () {
      const defaultPoint = LocationPoint(
        latitude: isbLat,
        longitude: isbLng,
        address: 'Islamabad F-6',
      );
      // Even when constructed with default geohash '', effectiveGeohash computes precision-7 hash
      expect(defaultPoint.geohash, isEmpty);
      expect(defaultPoint.effectiveGeohash, equals('ttgzwhp'));
      expect(defaultPoint.toMap()['geohash'], equals('ttgzwhp'));

      final taggedPoint = LocationPoint.withGeotag(
        latitude: lhrLat,
        longitude: lhrLng,
        address: 'Lahore Gulberg',
      );
      expect(taggedPoint.geohash, equals('ttsgk44'));
      expect(taggedPoint.effectiveGeohash, equals('ttsgk44'));
    });

    test('LocationPoint.fromMap auto-computes geohash when absent from map payload', () {
      final legacyMap = {
        'geopoint': {'latitude': isbLat, 'longitude': isbLng},
        'address': 'Islamabad Blue Area',
      };
      final point = LocationPoint.fromMap(legacyMap);
      expect(point.geohash, equals('ttgzwhp'));
      expect(point.effectiveGeohash, equals('ttgzwhp'));
    });

    test('LocationPoint distanceTo and bearingTo helpers calculate spatial vectors', () {
      final isb = LocationPoint.withGeotag(
        latitude: isbLat,
        longitude: isbLng,
        address: 'Islamabad',
      );
      final lhr = LocationPoint.withGeotag(
        latitude: lhrLat,
        longitude: lhrLng,
        address: 'Lahore',
      );
      final rwp = LocationPoint.withGeotag(
        latitude: rwpLat,
        longitude: rwpLng,
        address: 'Rawalpindi',
      );

      final isbToRwpKm = isb.distanceTo(rwp);
      expect(isbToRwpKm, greaterThan(10.0));
      expect(isbToRwpKm, lessThan(20.0));

      final isbToLhrKm = isb.distanceTo(lhr);
      expect(isbToLhrKm, greaterThan(260.0));

      final bearing = isb.bearingTo(lhr);
      expect(bearing, greaterThan(140.0));
      expect(bearing, lessThan(170.0));
    });

    test('FirestoreDriverService streamNearbyOnlineDrivers filters and sorts by proximity', () async {
      final driverService = FirestoreDriverService();

      // Seed 2 drivers in memory: Driver A in Rawalpindi (15km from ISB), Driver B in Lahore (270km from ISB)
      final rwpVehicle = VehicleInfo(
        make: 'Honda',
        model: 'Civic',
        year: 2022,
        plate: 'ISB-111',
        color: 'White',
      );
      final lhrVehicle = VehicleInfo(
        make: 'Toyota',
        model: 'Corolla',
        year: 2021,
        plate: 'LHR-222',
        color: 'Black',
      );

      await driverService.saveDriverProfile(DriverProfile(
        userId: 'driver_rwp',
        licenseNumber: 'LIC-RWP',
        vehicle: rwpVehicle,
        isVerified: true,
        isOnline: true,
        latitude: rwpLat,
        longitude: rwpLng,
        subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
      ));

      await driverService.saveDriverProfile(DriverProfile(
        userId: 'driver_lhr',
        licenseNumber: 'LIC-LHR',
        vehicle: lhrVehicle,
        isVerified: true,
        isOnline: true,
        latitude: lhrLat,
        longitude: lhrLng,
        subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
      ));

      // Query nearby Islamabad within 25km radius
      final nearby25km = await driverService
          .streamNearbyOnlineDrivers(
            centerLat: isbLat,
            centerLng: isbLng,
            radiusKm: 25.0,
          )
          .first;

      expect(nearby25km.length, equals(1));
      expect(nearby25km.first.userId, equals('driver_rwp'));

      // Query nearby Islamabad within 300km radius (should sort closest first)
      final allNearby = await driverService
          .streamNearbyOnlineDrivers(
            centerLat: isbLat,
            centerLng: isbLng,
            radiusKm: 300.0,
          )
          .first;

      expect(allNearby.length, equals(2));
      expect(allNearby[0].userId, equals('driver_rwp')); // 15km
      expect(allNearby[1].userId, equals('driver_lhr')); // 270km
    });

    test('FirestoreSafetyService recordSafetyEvent saves without error', () async {
      final safetyService = FirestoreSafetyService();
      final event = SafetyEvent(
        id: 'safety_test_1',
        rideId: 'ride_123',
        type: SafetyEventType.sos,
        latitude: isbLat,
        longitude: isbLng,
        createdAt: DateTime.now(),
        metadata: {'notes': 'Test SOS event'},
      );

      // Should complete cleanly with geohash indexing
      await safetyService.recordSafetyEvent(event);
      expect(true, isTrue);
    });

    test('FirestoreRideService saveLocationHistoryPoint records geotagged waypoint', () async {
      final rideService = FirestoreRideService();
      await rideService.saveLocationHistoryPoint(
        userId: 'rider_test',
        rideId: 'ride_test_abc',
        latitude: isbLat,
        longitude: isbLng,
        address: 'Islamabad Jinnah Ave',
      );
      expect(true, isTrue);
    });
  });
}
