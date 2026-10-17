import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/presentation/rider/ride_history_screen.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';

// Mock GeoPoint object to simulate Firestore SDK GeoPoint behavior
class FakeFirestoreGeoPoint {
  final double latitude;
  final double longitude;
  const FakeFirestoreGeoPoint(this.latitude, this.longitude);
}

// Mock Timestamp object to simulate Firestore SDK Timestamp behavior
class FakeFirestoreTimestamp {
  final DateTime _dateTime;
  FakeFirestoreTimestamp(this._dateTime);
  DateTime toDate() => _dateTime;
  @override
  String toString() => 'Timestamp(seconds=${_dateTime.millisecondsSinceEpoch ~/ 1000}, nanoseconds=0)';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationPoint & RideModel Firebase Serialization Audit', () {
    test('LocationPoint.fromMap flexibly parses Firestore GeoPoint objects', () {
      final fakeGeo = FakeFirestoreGeoPoint(33.7182, 73.0605);
      final map = {
        'geopoint': fakeGeo,
        'address': 'F-6 Super Market, Islamabad',
        'geohash': 'tp3ce8',
      };

      final point = LocationPoint.fromMap(map);
      expect(point.latitude, closeTo(33.7182, 0.0001));
      expect(point.longitude, closeTo(73.0605, 0.0001));
      expect(point.address, equals('F-6 Super Market, Islamabad'));
      expect(point.geohash, equals('tp3ce8'));
    });

    test('LocationPoint.fromMap parses standard map and lat/lng keys', () {
      final map = {
        'geopoint': {'latitude': 33.6844, 'longitude': 73.0479},
        'address': 'Zero Point Interchange, Islamabad',
      };
      final point = LocationPoint.fromMap(map);
      expect(point.latitude, closeTo(33.6844, 0.0001));
      expect(point.longitude, closeTo(73.0479, 0.0001));
      expect(point.address, equals('Zero Point Interchange, Islamabad'));
    });

    test('LocationPoint.fromMap throws FormatException when coordinates are missing', () {
      expect(
        () => LocationPoint.fromMap({'address': 'Invalid Spot'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('RideModel.fromMap correctly parses Firestore Timestamp objects without losing dates', () {
      final createdTime = DateTime(2026, 10, 17, 10, 30);
      final completedTime = DateTime(2026, 10, 17, 10, 52);

      final rideMap = {
        'id': 'ride_audit_001',
        'riderId': 'rider_test_123',
        'driverId': 'driver_test_456',
        'status': 'COMPLETED',
        'pickup': {
          'geopoint': {'latitude': 33.7077, 'longitude': 73.0501},
          'address': 'Centaurus Mall, Jinnah Avenue, Islamabad',
          'geohash': 'tp3ce1',
        },
        'dropoff': {
          'geopoint': {'latitude': 33.5651, 'longitude': 72.8524},
          'address': 'Islamabad International Airport, Islamabad',
          'geohash': 'tp39c0',
        },
        'offeredFare': 1800.0,
        'acceptedFare': 1800.0,
        'suggestedFare': 1750.0,
        'distanceKm': 28.5,
        'durationMin': 32.0,
        'commissionAmount': 0.0,
        'paymentMethod': 'CASH',
        'paymentStatus': 'paid',
        'createdAt': FakeFirestoreTimestamp(createdTime),
        'completedAt': FakeFirestoreTimestamp(completedTime),
      };

      final ride = RideModel.fromMap(rideMap, docId: 'ride_audit_001');
      expect(ride.id, equals('ride_audit_001'));
      expect(ride.status, equals(RideStatus.completed));
      expect(ride.pickup.address, contains('Centaurus'));
      expect(ride.dropoff.address, contains('Airport'));
      expect(ride.acceptedFare, equals(1800.0));
      expect(ride.createdAt.year, equals(2026));
      expect(ride.createdAt.minute, equals(30));
      expect(ride.completedAt?.minute, equals(52));
    });
  });

  group('FirestoreRideService History & Composite Indexing Audit', () {
    late FirestoreRideService service;

    setUp(() {
      service = FirestoreRideService();
    });

    test('saveRideHistory stores trips and fetchRideHistoryPage queries by user and status', () async {
      final trip1 = RideModel(
        id: 'trip_hist_001',
        riderId: 'rider_audit_user',
        driverId: 'driver_audit_99',
        status: RideStatus.completed,
        pickup: const LocationPoint(
          latitude: 33.7182,
          longitude: 73.0605,
          address: 'Blue Area, Islamabad',
        ),
        dropoff: const LocationPoint(
          latitude: 33.6844,
          longitude: 73.0479,
          address: 'Zero Point, Islamabad',
        ),
        offeredFare: 400.0,
        acceptedFare: 400.0,
        suggestedFare: 380.0,
        distanceKm: 5.5,
        durationMin: 12.0,
        pin: '1234',
        createdAt: DateTime(2026, 10, 16, 14, 0),
        completedAt: DateTime(2026, 10, 16, 14, 15),
      );

      final trip2 = RideModel(
        id: 'trip_hist_002',
        riderId: 'rider_audit_user',
        driverId: 'driver_audit_99',
        status: RideStatus.cancelled,
        pickup: const LocationPoint(
          latitude: 33.7380,
          longitude: 73.0845,
          address: 'Daman-e-Koh, Islamabad',
        ),
        dropoff: const LocationPoint(
          latitude: 33.7077,
          longitude: 73.0501,
          address: 'Centaurus Mall, Islamabad',
        ),
        offeredFare: 650.0,
        suggestedFare: 600.0,
        distanceKm: 8.2,
        durationMin: 18.0,
        pin: '5678',
        createdAt: DateTime(2026, 10, 17, 9, 30),
      );

      final otherRiderTrip = RideModel(
        id: 'trip_hist_003',
        riderId: 'other_rider_77',
        status: RideStatus.completed,
        pickup: const LocationPoint(latitude: 33.6, longitude: 73.0, address: 'Spot A'),
        dropoff: const LocationPoint(latitude: 33.62, longitude: 73.02, address: 'Spot B'),
        offeredFare: 300.0,
        suggestedFare: 300.0,
        distanceKm: 3.0,
        durationMin: 8.0,
        pin: '9999',
        createdAt: DateTime(2026, 10, 17, 10, 0),
      );

      // Push history data
      await service.saveRideHistory(trip1);
      await service.saveRideHistory(trip2);
      await service.saveRideHistory(otherRiderTrip);

      // Query rider history (composite pattern: riderId ASC, createdAt DESC)
      final pageAll = await service.fetchRideHistoryPage(
        riderId: 'rider_audit_user',
      );
      expect(pageAll.rides.length, equals(2));
      expect(pageAll.rides.first.id, equals('trip_hist_002')); // Newest first

      // Query rider history filtered by status (composite pattern: riderId ASC, status ASC, createdAt DESC)
      final pageCompleted = await service.fetchRideHistoryPage(
        riderId: 'rider_audit_user',
        status: 'COMPLETED',
      );
      expect(pageCompleted.rides.length, equals(1));
      expect(pageCompleted.rides.first.id, equals('trip_hist_001'));
      expect(pageCompleted.rides.first.pickup.address, contains('Blue Area'));

      // Query driver history (composite pattern: driverId ASC, createdAt DESC)
      final pageDriver = await service.fetchRideHistoryPage(
        riderId: 'driver_audit_99',
        asDriver: true,
      );
      expect(pageDriver.rides.length, equals(2));
    });
  });

  group('RideHistoryScreen UI Audit', () {
    testWidgets('Renders RideHistoryScreen with trip card details, fare, and filter chips', (tester) async {
      final sampleRide = RideModel(
        id: 'ui_ride_001',
        riderId: 'rider_ui_user',
        status: RideStatus.completed,
        pickup: const LocationPoint(
          latitude: 33.7294,
          longitude: 73.0931,
          address: 'F-7 Jinnah Super Market, Islamabad',
        ),
        dropoff: const LocationPoint(
          latitude: 33.7077,
          longitude: 73.0501,
          address: 'Centaurus Mall, Islamabad',
        ),
        offeredFare: 350.0,
        acceptedFare: 350.0,
        suggestedFare: 330.0,
        distanceKm: 4.8,
        durationMin: 11.0,
        pin: '1234',
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
      );

      final authProvider = AuthProvider(
        initialUser: AppUser(
          id: 'rider_ui_user',
          phone: '+923001234567',
          fullName: 'Test Rider',
          role: UserRole.rider,
          rating: 4.9,
          totalRides: 12,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final firestoreService = FirestoreRideService();
      await firestoreService.saveRideHistory(sampleRide);

      final rideProvider = RideProvider(
        firestore: firestoreService,
        initialHistory: [sampleRide],
      );

      await tester.pumpWidget(
        CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: authProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<RideProvider>(
                  notifier: rideProvider,
                  child: child,
                ),
          ],
          child: const MaterialApp(
            home: RideHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check app bar title
      expect(find.text('My Ride History'), findsOneWidget);

      // Check filter chips
      expect(find.text('All Rides'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);

      // Check ride card contents
      expect(find.textContaining('F-7 Jinnah Super'), findsOneWidget);
      expect(find.textContaining('Centaurus Mall'), findsOneWidget);
      expect(find.text('PKR 350'), findsOneWidget);
      expect(find.text('0% Fee'), findsOneWidget);
      expect(find.text('4.8 km'), findsOneWidget);
      expect(find.text('11 min'), findsOneWidget);
      expect(find.text('Completed'), findsNWidgets(2)); // Filter chip + status badge
    });

    testWidgets('Renders empty state when user has no trip history', (tester) async {
      final authProvider = AuthProvider(
        initialUser: AppUser(
          id: 'empty_user',
          phone: '+923000000000',
          fullName: 'New User',
          role: UserRole.rider,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final rideProvider = RideProvider(initialHistory: []);

      await tester.pumpWidget(
        CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: authProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<RideProvider>(
                  notifier: rideProvider,
                  child: child,
                ),
          ],
          child: const MaterialApp(
            home: RideHistoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Ride History Found'), findsOneWidget);
      expect(find.text('Book a Ride Now'), findsOneWidget);
    });
  });
}
