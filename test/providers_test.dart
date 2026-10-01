import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
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

    test('DriverProvider toggles online status and credits trip earnings', () {
      final driver = DriverProvider();
      expect(driver.isOnline, true);

      driver.toggleOnline(false);
      expect(driver.isOnline, false);

      final prevEarnings = driver.totalEarnings;
      driver.creditTripEarnings(30.0);
      expect(driver.totalEarnings, prevEarnings + 30.0);

      driver.requestInstantPayout();
      expect(driver.driverProfile.payoutStatus, 'paid_out');

      driver.dispose();
    });

    test('RideProvider manages complete bidding and PIN lifecycle', () {
      final rideProv = RideProvider();
      final driverProv = DriverProvider();

      expect(rideProv.currentRide, isNull);

      // Rider requests ride
      rideProv.requestRide(
        riderId: 'rider_01',
        pickup: const LocationPoint(latitude: 37.77, longitude: -122.41, address: 'A'),
        dropoff: const LocationPoint(latitude: 37.78, longitude: -122.40, address: 'B'),
        offeredFare: 12.0,
        distanceKm: 3.5,
        durationMin: 10.0,
        currentDriver: driverProv.driverProfile,
      );

      expect(rideProv.currentRide, isNotNull);
      expect(rideProv.activeOffers.length, 2);

      // Driver submits counter-offer
      rideProv.submitDriverCounterOffer(
        rideId: rideProv.currentRide!.id,
        driver: driverProv.driverProfile,
        counterFare: 14.50,
      );
      expect(rideProv.activeOffers.length, 3);

      // Rider accepts offer
      final chosenOffer = rideProv.activeOffers.first;
      rideProv.acceptOffer(chosenOffer.id);
      expect(rideProv.currentRide!.status, RideStatus.accepted);

      // Driver arrives
      rideProv.driverArrived();
      expect(rideProv.currentRide!.status, RideStatus.driverArrived);

      // Verify PIN
      final pin = rideProv.currentRide!.pin;
      expect(rideProv.startTripWithPin('0000'), isFalse);
      expect(rideProv.startTripWithPin(pin), isTrue);
      expect(rideProv.currentRide!.status, RideStatus.inProgress);

      // Complete trip
      final completed = rideProv.completeTrip();
      expect(completed, isNotNull);
      expect(completed!.status, RideStatus.completed);
      expect(rideProv.currentRide, isNull);
      expect(rideProv.rideHistory.length, 1);

      rideProv.dispose();
      driverProv.dispose();
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

    test('AdminProvider verifies pending driver', () {
      final admin = AdminProvider();
      expect(admin.pendingDrivers.isNotEmpty, isTrue);

      final firstId = admin.pendingDrivers.first.userId;
      admin.verifyDriver(firstId, true);
      expect(admin.pendingDrivers.any((d) => d.userId == firstId), isFalse);

      admin.dispose();
    });
  });
}
