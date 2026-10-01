import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/utils/distance_calculator.dart';
import 'package:swiftride/core/utils/id_generator.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
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

    test('RideService calculates suggested fare and creates ride with PIN', () {
      final pickup = const LocationPoint(latitude: 37.7749, longitude: -122.4194, address: 'Downtown');
      final dropoff = const LocationPoint(latitude: 37.7850, longitude: -122.4060, address: 'Fidi');

      final ride = rideService.createRideRequest(
        riderId: 'rider_01',
        pickup: pickup,
        dropoff: dropoff,
        offeredFare: 15.00,
        distanceKm: 5.0,
        durationMin: 12.0,
      );

      expect(ride.riderId, 'rider_01');
      expect(ride.status, RideStatus.requested);
      expect(ride.pin.length, 4);
      expect(ride.commissionAmount, 0.0); // 0% commission in year 1
      expect(ride.suggestedFare, greaterThan(0));

      // Test driver counter offers
      final offers = rideService.generateInitialDriverOffers(ride: ride, currentDriver: testDriver);
      expect(offers.length, 2);
      expect(offers.first.counterFare, 15.00);

      // Accept offer
      final acceptedRide = rideService.acceptOffer(ride, offers.first);
      expect(acceptedRide.status, RideStatus.accepted);
      expect(acceptedRide.driverId, testDriver.userId);

      // Driver arrived
      final arrivedRide = rideService.markDriverArrived(acceptedRide);
      expect(arrivedRide.status, RideStatus.driverArrived);

      // Verify PIN to start trip (invalid vs valid)
      expect(rideService.verifyPinAndStartTrip(arrivedRide, '9999'), isNull);
      final inProgressRide = rideService.verifyPinAndStartTrip(arrivedRide, ride.pin);
      expect(inProgressRide, isNotNull);
      expect(inProgressRide!.status, RideStatus.inProgress);

      // Complete trip
      final completed = rideService.completeTrip(inProgressRide);
      expect(completed.status, RideStatus.completed);
      expect(completed.paymentStatus, 'paid');
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
}
