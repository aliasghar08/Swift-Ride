import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/providers/admin_provider.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/providers/safety_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Pure Custom Providers State Management Tests', () {
    test('AuthProvider switches roles and updates user stats', () {
      final auth = AuthProvider();
      expect(auth.activeRole, UserRole.rider);

      auth.switchRole(UserRole.driver);
      expect(auth.activeRole, UserRole.driver);

      auth.switchRole(UserRole.admin);
      expect(auth.activeRole, UserRole.admin);

      final initialRides = auth.currentUser.totalRides;
      auth.incrementRidesCount();
      expect(auth.currentUser.totalRides, initialRides + 1);

      auth.dispose();
    });

    test('DriverProvider starts with no fabricated earnings and tracks trips', () {
      final driver = DriverProvider();

      // Regression guard: this provider used to be seeded with a made-up driver
      // (plate 7XYZ890, 318 rides, PKR 4,250 earned) that the cockpit displayed
      // as real takings.
      expect(driver.isOnline, isFalse);
      expect(driver.totalEarnings, 0);
      expect(driver.totalRides, 0);
      expect(driver.driverProfile.userId, isEmpty);
      expect(driver.driverProfile.totalEarnings, 0);

      driver.creditTripEarnings(30.0);
      expect(driver.totalEarnings, 30.0);

      driver.dispose();
    });

    test('toggleOnline does not claim success without a backend', () async {
      final driver = DriverProvider();

      // Going online is persisted through the `toggleOnline` Cloud Function so
      // the onRideCreated trigger can geohash-query available drivers. With no
      // backend the switch must report the failure rather than flipping to
      // "online" while dispatch still cannot see this driver.
      final error = await driver.toggleOnline(true, latitude: 33.70, longitude: 73.05);

      expect(error, isNotNull);
      expect(driver.isOnline, isFalse);
      expect(driver.availabilityError, isNotNull);

      driver.dispose();
    });

    test('RideProvider never fabricates a ride when the backend is unreachable', () async {
      // Regression guard. This provider used to invent a ride id and two fake
      // driver counter-offers entirely in memory, so a rider could "book" a trip
      // that never existed.
      final rideProv = RideProvider();

      expect(rideProv.currentRide, isNull);

      final rideId = await rideProv.requestRide(
        pickup: const LocationPoint(latitude: 37.77, longitude: -122.41, address: 'A'),
        dropoff: const LocationPoint(latitude: 37.78, longitude: -122.40, address: 'B'),
        offeredFare: 12.0,
        distanceKm: 3.5,
        durationMin: 10.0,
      );

      // No Firebase in the test environment: this must fail honestly rather than
      // producing a synthetic ride.
      expect(rideId, isNull);
      expect(rideProv.currentRide, isNull);
      expect(rideProv.activeOffers, isEmpty);
      expect(rideProv.rideHistory, isEmpty);
      expect(rideProv.lastError, isNotNull);

      rideProv.dispose();
    });

    test('RideProvider watches open requests for drivers', () {
      final rideProv = RideProvider();

      // streamAvailableRides() previously had no subscriber at all, so a rider's
      // request was never shown to any driver and no trip could be matched.
      expect(rideProv.availableRides, isEmpty);

      rideProv.watchAvailableRides();
      rideProv.watchAvailableRides(); // idempotent: must not open a second stream

      expect(rideProv.availableRides, isEmpty);

      rideProv.stopWatchingAvailableRides();
      expect(rideProv.availableRides, isEmpty);

      rideProv.dispose();
    });

    test('LocationProvider updates coordinates and heading', () {
      final loc = LocationProvider(autoStart: false);
      expect(loc.latitude, greaterThan(0));

      loc.updatePosition(37.7900, -122.4000, heading: 90.0);
      expect(loc.latitude, 37.7900);
      expect(loc.longitude, -122.4000);
      expect(loc.heading, 90.0);

      loc.dispose();
    });

    test('SafetyProvider dispatches SOS and creates share token', () {
      final safety = SafetyProvider();
      expect(safety.safetyEvents, isEmpty);

      final event = safety.triggerSos(
        rideId: 'ride_test_99',
        userId: 'user_test_99',
        latitude: 37.77,
        longitude: -122.41,
        message: 'Need help',
      );
      expect(safety.safetyEvents.length, 1);
      expect(event.rideId, 'ride_test_99');

      final token = safety.generateShareToken();
      expect(token.length, 16);

      safety.dispose();
    });

    test('AdminProvider starts with no fabricated applicant queue', () async {
      final admin = AdminProvider();

      // Regression guard: this provider used to seed a made-up applicant
      // ("driver_sarah_303", Honda Accord) that an operator could approve or
      // reject, writing to a driver who did not exist.
      expect(admin.pendingDrivers, isEmpty);

      // Without a backend the decision must fail closed rather than reporting
      // success against a driver that was never verified.
      final ok = await admin.verifyDriver('driver_sarah_303', true);
      expect(ok, isFalse);

      admin.dispose();
    });
  });
}
