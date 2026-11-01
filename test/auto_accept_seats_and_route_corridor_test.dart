import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
import 'package:swiftride/services/native_map_service.dart';
import 'package:swiftride/services/route_corridor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto-Accept Rides Module Tests', () {
    late DriverViewModel driverVM;

    setUp(() {
      driverVM = DriverViewModel();
    });

    test('Initial mode is AutoAcceptMode.off', () {
      expect(driverVM.autoAcceptMode, equals(AutoAcceptMode.off));
      expect(driverVM.autoAcceptAiValuedRides, isFalse);
      expect(driverVM.autoAcceptCurrentRate, isFalse);
    });

    test('shouldAutoAccept returns false when mode is off', () {
      expect(
        driverVM.shouldAutoAccept(offeredFare: 500.0, aiValuation: 400.0),
        isFalse,
      );
    });

    test('AutoAcceptMode.currentRate auto-accepts offered fares >= PKR 50', () {
      driverVM.setAutoAcceptMode(AutoAcceptMode.currentRate);
      expect(driverVM.autoAcceptCurrentRate, isTrue);

      // Above floor
      expect(
        driverVM.shouldAutoAccept(offeredFare: 150.0, aiValuation: 200.0),
        isTrue,
      );
      // At floor
      expect(
        driverVM.shouldAutoAccept(offeredFare: 50.0, aiValuation: 100.0),
        isTrue,
      );
      // Below floor
      expect(
        driverVM.shouldAutoAccept(offeredFare: 40.0, aiValuation: 50.0),
        isFalse,
      );
    });

    test('AutoAcceptMode.aiValuation auto-accepts within ±5% or above AI valuation', () {
      driverVM.setAutoAcceptMode(AutoAcceptMode.aiValuation);
      expect(driverVM.autoAcceptAiValuedRides, isTrue);

      // Exact match
      expect(
        driverVM.shouldAutoAccept(offeredFare: 200.0, aiValuation: 200.0),
        isTrue,
      );
      // Within -5% (e.g. 190 on 200 is -5%)
      expect(
        driverVM.shouldAutoAccept(offeredFare: 190.0, aiValuation: 200.0),
        isTrue,
      );
      // Above AI market valuation (+25%)
      expect(
        driverVM.shouldAutoAccept(offeredFare: 250.0, aiValuation: 200.0),
        isTrue,
      );
      // Below -5% (e.g. 180 on 200 is -10%)
      expect(
        driverVM.shouldAutoAccept(offeredFare: 180.0, aiValuation: 200.0),
        isFalse,
      );
    });
  });

  group('Seat Position & Multi-Seat Increment Tests', () {
    late RiderViewModel riderVM;

    setUp(() {
      riderVM = RiderViewModel();
      riderVM.selectVehicleType(VehicleType.car);
    });

    test('Default 1-seat selection starts with Any Seat', () {
      expect(riderVM.bookedSeats, equals(1));
      expect(riderVM.seatPreference, equals('Any'));
    });

    test('Selecting 1 seat allows single position', () {
      riderVM.toggleSeatPosition('Window Seat (Left)');
      expect(riderVM.selectedSeatPositions, contains('Window Seat (Left)'));
      expect(riderVM.seatPreference, equals('Window Seat (Left)'));

      riderVM.toggleSeatPosition('Front Passenger');
      expect(riderVM.selectedSeatPositions, contains('Front Passenger'));
      expect(riderVM.selectedSeatPositions.length, equals(1));
    });

    test('Incrementing to 2 seats allows choosing up to 2 positions', () {
      riderVM.setBookedSeats(2);
      expect(riderVM.bookedSeats, equals(2));

      riderVM.toggleSeatPosition('Window Seat (Left)');
      riderVM.toggleSeatPosition('Window Seat (Right)');

      expect(riderVM.selectedSeatPositions.length, equals(2));
      expect(riderVM.selectedSeatPositions, contains('Window Seat (Left)'));
      expect(riderVM.selectedSeatPositions, contains('Window Seat (Right)'));
      expect(riderVM.seatPreference, equals('Window Seat (Left), Window Seat (Right)'));
    });

    test('Incrementing to 3 seats allows choosing up to 3 positions', () {
      riderVM.setBookedSeats(3);
      expect(riderVM.bookedSeats, equals(3));

      riderVM.toggleSeatPosition('Front Passenger');
      riderVM.toggleSeatPosition('Window Seat (Left)');
      riderVM.toggleSeatPosition('Middle Seat');

      expect(riderVM.selectedSeatPositions.length, equals(3));
      expect(riderVM.selectedSeatPositions, contains('Front Passenger'));
      expect(riderVM.selectedSeatPositions, contains('Window Seat (Left)'));
      expect(riderVM.selectedSeatPositions, contains('Middle Seat'));
    });

    test('Booking all 4 seats automatically reserves the entire car', () {
      riderVM.setBookedSeats(4);
      expect(riderVM.bookedSeats, equals(4));
      expect(riderVM.seatPreference, equals('Entire Car (All 4 Seats)'));
      expect(riderVM.selectedSeatPositions, contains('Entire Car (All 4 Seats)'));
    });

    test('Decreasing from 4 seats resets preference gracefully', () {
      riderVM.setBookedSeats(4);
      expect(riderVM.seatPreference, equals('Entire Car (All 4 Seats)'));

      riderVM.setBookedSeats(2);
      expect(riderVM.bookedSeats, equals(2));
      expect(riderVM.selectedSeatPositions.contains('Entire Car (All 4 Seats)'), isFalse);
    });
  });

  group('Route Corridor & Minimal Petrol Carpool Matching Tests', () {
    final activeRide = RideModel(
      id: 'active_ride_1',
      riderId: 'rider_main',
      driverId: 'driver_1',
      pickup: const LocationPoint(
        address: 'Clock Tower, Faisalabad',
        latitude: 31.4187,
        longitude: 73.0791,
      ),
      dropoff: const LocationPoint(
        address: 'D-Ground, People\'s Colony, Faisalabad',
        latitude: 31.4110,
        longitude: 73.1110,
      ),
      offeredFare: 450.0,
      acceptedFare: 450.0,
      suggestedFare: 450.0,
      distanceKm: 4.5,
      durationMin: 12.0,
      vehicleType: 'car',
      bookedSeats: 1, // 3 seats empty!
      pin: '1234',
      status: RideStatus.inProgress,
      createdAt: DateTime.now(),
    );

    final activeRoutePoints = [
      const LatLng(31.4187, 73.0791), // Clock Tower
      const LatLng(31.4150, 73.0950), // Midway along corridor
      const LatLng(31.4110, 73.1110), // D-Ground
    ];

    test('Correctly identifies empty seats available in active ride', () {
      expect(activeRide.totalSeats, equals(4));
      expect(activeRide.emptySeats, equals(3));
      expect(activeRide.hasEmptySeats, isTrue);
    });

    test('EnRoute candidate directly along route is matched with positive net profit', () {
      final candidate = RideModel(
        id: 'candidate_1',
        riderId: 'rider_along_way',
        pickup: const LocationPoint(
          address: 'Canal Road Crossing (Near Corridor)',
          latitude: 31.4152,
          longitude: 73.0952, // 20 meters from midway point
        ),
        dropoff: const LocationPoint(
          address: 'Kohinoor City (Near D-Ground)',
          latitude: 31.4115,
          longitude: 73.1105, // 50 meters from destination
        ),
        offeredFare: 250.0,
        suggestedFare: 250.0,
        distanceKm: 2.1,
        durationMin: 6.0,
        vehicleType: 'car',
        bookedSeats: 1,
        pin: '5678',
        status: RideStatus.requested,
        createdAt: DateTime.now(),
      );

      final match = RouteCorridorService.evaluateCandidate(
        activeRide: activeRide,
        activeRoutePoints: activeRoutePoints,
        candidateRide: candidate,
      );

      expect(match, isNotNull);
      expect(match!.detourKm, lessThan(1.0)); // Minimal detour
      expect(match.extraPetrolCost, lessThan(30.0)); // < PKR 30 petrol
      expect(match.netProfitBoost, greaterThan(200.0)); // Substantial net profit boost
      expect(match.ride.id, equals('candidate_1'));
    });

    test('Candidate exceeding available empty seats is rejected', () {
      final tooManyPassengers = RideModel(
        id: 'candidate_large_group',
        riderId: 'group_rider',
        pickup: const LocationPoint(
          address: 'Near Path',
          latitude: 31.4152,
          longitude: 73.0952,
        ),
        dropoff: const LocationPoint(
          address: 'Near Dropoff',
          latitude: 31.4115,
          longitude: 73.1105,
        ),
        offeredFare: 600.0,
        suggestedFare: 600.0,
        distanceKm: 2.1,
        durationMin: 6.0,
        vehicleType: 'car',
        bookedSeats: 4, // Exceeds 3 empty seats!
        pin: '9999',
        status: RideStatus.requested,
        createdAt: DateTime.now(),
      );

      final match = RouteCorridorService.evaluateCandidate(
        activeRide: activeRide,
        activeRoutePoints: activeRoutePoints,
        candidateRide: tooManyPassengers,
      );

      expect(match, isNull);
    });

    test('Candidate with excessive detour far from route is rejected to prevent petrol burn', () {
      final distantCandidate = RideModel(
        id: 'candidate_far_off',
        riderId: 'far_rider',
        pickup: const LocationPoint(
          address: 'Motorway M-4 Interchange (8 km off course)',
          latitude: 31.4900,
          longitude: 73.0000,
        ),
        dropoff: const LocationPoint(
          address: 'Millat Town',
          latitude: 31.4800,
          longitude: 73.0200,
        ),
        offeredFare: 200.0,
        suggestedFare: 200.0,
        distanceKm: 5.0,
        durationMin: 15.0,
        vehicleType: 'car',
        bookedSeats: 1,
        pin: '1111',
        status: RideStatus.requested,
        createdAt: DateTime.now(),
      );

      final match = RouteCorridorService.evaluateCandidate(
        activeRide: activeRide,
        activeRoutePoints: activeRoutePoints,
        candidateRide: distantCandidate,
      );

      expect(match, isNull);
    });

    test('findEnRouteMatches filters and ranks matches by net profit', () {
      final candidates = [
        RideModel(
          id: 'cand_1',
          riderId: 'r1',
          pickup: const LocationPoint(address: 'P1', latitude: 31.4152, longitude: 73.0952),
          dropoff: const LocationPoint(address: 'D1', latitude: 31.4115, longitude: 73.1105),
          offeredFare: 200.0,
          suggestedFare: 200.0,
          distanceKm: 2.0,
          durationMin: 5.0,
          vehicleType: 'car',
          bookedSeats: 1,
          pin: '2222',
          status: RideStatus.requested,
          createdAt: DateTime.now(),
        ),
        RideModel(
          id: 'cand_2_higher_profit',
          riderId: 'r2',
          pickup: const LocationPoint(address: 'P2', latitude: 31.4160, longitude: 73.0900),
          dropoff: const LocationPoint(address: 'D2', latitude: 31.4112, longitude: 73.1108),
          offeredFare: 350.0,
          suggestedFare: 350.0,
          distanceKm: 3.0,
          durationMin: 8.0,
          vehicleType: 'car',
          bookedSeats: 1,
          pin: '3333',
          status: RideStatus.requested,
          createdAt: DateTime.now(),
        ),
      ];

      final matches = RouteCorridorService.findEnRouteMatches(
        activeRide: activeRide,
        activeRoutePoints: activeRoutePoints,
        candidateRides: candidates,
      );

      expect(matches.length, equals(2));
      // Highest net profit ranked first
      expect(matches.first.ride.id, equals('cand_2_higher_profit'));
      expect(matches.first.netProfitBoost, greaterThan(matches.last.netProfitBoost));
    });
  });
}
