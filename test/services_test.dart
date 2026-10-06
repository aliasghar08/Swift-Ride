import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/utils/geohash_util.dart';
import 'package:swiftride/core/utils/distance_calculator.dart';
import 'package:swiftride/core/utils/id_generator.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/subscription_model.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/services/admin_service.dart';
import 'package:swiftride/services/driver_service.dart';
import 'package:swiftride/services/location_service.dart';
import 'package:swiftride/services/ride_service.dart';
import 'package:swiftride/services/safety_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Pure Flutter Services & Domain Models Tests', () {
    late RideService rideService;
    late DriverService driverService;
    late LocationService locationService;
    late SafetyService safetyService;
    late AdminService adminService;

    final testDriver = DriverProfile(
      userId: 'driver_test_01',
      licenseNumber: 'DL-TEST-999',
      vehicle: const VehicleInfo(
        make: 'Toyota',
        model: 'Camry Hybrid',
        year: 2023,
        plate: 'TEST-123',
        color: 'Black',
      ),
      isVerified: true,
      isOnline: true,
      subscriptionStatus: SubscriptionStatus.trial,
      subscriptionExpiresAt: DateTime.now().add(const Duration(days: 300)),
      createdAt: DateTime.now(),
    );

    setUp(() {
      rideService = RideService();
      driverService = DriverService();
      locationService = LocationService();
      safetyService = SafetyService();
      adminService = AdminService();
    });

    tearDown(() {
      locationService.dispose();
    });

    test('RideService builds a bid from the signed-in driver, not a placeholder', () {
      // The lifecycle itself is covered by test/ride_lifecycle_test.dart, which
      // exercises the real Firestore path. The local simulation that this test
      // used to drive has been deleted.
      final offer = rideService.createDriverCounterOffer(
        rideId: 'ride_1',
        driver: testDriver,
        driverName: 'Ayesha Khan',
        counterFare: 640,
      );

      expect(offer.rideId, 'ride_1');
      expect(offer.driverId, testDriver.userId);
      // Regression guard: this was hardcoded to "Marcus Vance (You)", so a rider
      // saw a bid from a driver who did not exist.
      expect(offer.driverName, 'Ayesha Khan');
      expect(offer.counterFare, 640);
      expect(offer.vehicleSummary, isNotEmpty);
      expect(offer.vehicleSummary, contains('Black Toyota Camry Hybrid (TEST-123)'));
    });

    test('RideService falls back to a neutral name when none is provided', () {
      final offer = rideService.createDriverCounterOffer(
        rideId: 'ride_2',
        driver: testDriver,
        driverName: '   ',
        counterFare: 500,
      );

      // Never an empty label on the rider's screen.
      expect(offer.driverName, 'Your driver');
    });

    test('DriverService credits 100% earnings with \$0 commission', () {
      final initialEarnings = testDriver.totalEarnings;
      final tripFare = 24.50;

      final updated = driverService.creditTripEarnings(testDriver, tripFare);
      expect(updated.totalEarnings, initialEarnings + tripFare);
      expect(updated.totalRides, testDriver.totalRides + 1);
    });

    test('SafetyService creates SOS alert with coordinates and share token', () {
      final alert = safetyService.createSosAlert(
        rideId: 'ride_123',
        userId: 'rider_01',
        latitude: 37.7749,
        longitude: -122.4194,
        message: 'Test SOS Alert',
      );

      expect(alert.rideId, 'ride_123');
      expect(alert.metadata['alertLevel'], 'CRITICAL');
      expect(alert.latitude, 37.7749);

      final token = safetyService.generateShareToken();
      expect(token.length, 16);
    });

    test('AdminService calculates platform KPIs correctly', () {
      final kpis = adminService.computePlatformKpis(
        rideHistory: [],
        currentRide: null,
        allDrivers: [testDriver],
        pendingDrivers: [],
      );

      expect(kpis.activeDrivers, 1);
      expect(kpis.grossMarketplaceValue, 0.0);
      expect(kpis.driverCommissionSavings, 0.0);
    });

    test('DistanceCalculator calculates Haversine and 13% savings accurately', () {
      final dist = DistanceCalculator.haversineDistance(37.7749, -122.4194, 37.7850, -122.4060);
      expect(dist, greaterThan(1.0));
      expect(dist, lessThan(3.0));

      final savings = DistanceCalculator.calculateZeroCommissionSavings(100.0);
      expect(savings, 13.0); // $13 saved on $100 fare vs 13% incumbent commission
    });

    test('IdGenerator generates unique IDs and 4-digit PINs', () {
      final pin = IdGenerator.generatePin();
      expect(pin.length, 4);
      expect(int.tryParse(pin), isNotNull);

      final id = IdGenerator.generateId(prefix: 'ride_');
      expect(id.startsWith('ride_'), isTrue);
    });
  });

  group('GeohashUtil', () {
    test('matches the canonical reference vector', () {
      // Dispatch queries online drivers by geohash bounds, so an encoding that
      // disagrees with the backend silently matches nobody.
      expect(GeohashUtil.encode(42.6, -5.6, 5), 'ezs42');
    });

    test('encodes Islamabad at the precision used for dispatch', () {
      expect(GeohashUtil.encode(33.6844, 73.0479, 7), 'ttgzwhp');
    });

    test('respects the requested precision', () {
      expect(GeohashUtil.encode(33.6844, 73.0479, 5).length, 5);
      expect(GeohashUtil.encode(33.6844, 73.0479, 9).length, 9);
    });
  });

}
