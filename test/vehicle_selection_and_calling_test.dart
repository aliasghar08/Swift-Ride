import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/trip_economics_model.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
import 'package:swiftride/services/pricing_ml_service.dart';
import 'package:swiftride/services/fuel_price_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VehicleType Model Tests', () {
    test('VehicleType properties for car, bike, and rikshaw', () {
      expect(VehicleType.car.title, contains('Car'));
      expect(VehicleType.car.seats, equals(4));
      expect(VehicleType.car.fareMultiplier, equals(1.0));
      expect(VehicleType.car.minFare, equals(80.0));

      expect(VehicleType.bike.title, contains('Bike'));
      expect(VehicleType.bike.seats, equals(1));
      expect(VehicleType.bike.fareMultiplier, equals(0.45));
      expect(VehicleType.bike.minFare, equals(40.0));

      expect(VehicleType.rikshaw.title, contains('Rikshaw'));
      expect(VehicleType.rikshaw.seats, equals(2));
      expect(VehicleType.rikshaw.fareMultiplier, equals(0.70));
      expect(VehicleType.rikshaw.minFare, equals(50.0));

      expect(VehicleType.car.averageMileageKmPerL, equals(10.0));
      expect(VehicleType.rikshaw.averageMileageKmPerL, equals(22.0));
      expect(VehicleType.bike.averageMileageKmPerL, equals(30.0));
    });

    test('VehicleType fare calculation rounds to 5 PKR and respects floor', () {
      const baseCarFare = 200.0;
      // Car: 200 * 1.0 = 200
      expect(VehicleType.car.calculateFare(baseCarFare), equals(200.0));

      // Bike: 200 * 0.45 = 90
      expect(VehicleType.bike.calculateFare(baseCarFare), equals(90.0));

      // Rikshaw: 200 * 0.70 = 140
      expect(VehicleType.rikshaw.calculateFare(baseCarFare), equals(140.0));

      // Floor test with small base fare
      const smallCarFare = 50.0;
      expect(VehicleType.bike.calculateFare(smallCarFare), equals(40.0)); // minFare is 40
      expect(VehicleType.rikshaw.calculateFare(smallCarFare), equals(50.0)); // minFare is 50
    });

    test('VehicleType fromString parses diverse inputs', () {
      expect(VehicleTypeX.fromString('car'), equals(VehicleType.car));
      expect(VehicleTypeX.fromString('BIKE'), equals(VehicleType.bike));
      expect(VehicleTypeX.fromString('moto'), equals(VehicleType.bike));
      expect(VehicleTypeX.fromString('motorcycle'), equals(VehicleType.bike));
      expect(VehicleTypeX.fromString('rikshaw'), equals(VehicleType.rikshaw));
      expect(VehicleTypeX.fromString('rickshaw'), equals(VehicleType.rikshaw));
      expect(VehicleTypeX.fromString('auto'), equals(VehicleType.rikshaw));
      expect(VehicleTypeX.fromString('unknown'), equals(VehicleType.car));
      expect(VehicleTypeX.fromString(null), equals(VehicleType.car));
    });
  });

  group('RideModel vehicleType persistence', () {
    test('serializes and deserializes vehicleType', () {
      final ride = RideModel(
        id: 'ride_123',
        riderId: 'rider_abc',
        pickup: const LocationPoint(latitude: 31.27, longitude: 72.33, address: 'Jhang City'),
        dropoff: const LocationPoint(latitude: 31.29, longitude: 72.35, address: 'Saddar'),
        offeredFare: 120.0,
        suggestedFare: 110.0,
        distanceKm: 4.5,
        durationMin: 12.0,
        pin: '4321',
        createdAt: DateTime.now(),
        vehicleType: 'rikshaw',
      );

      final map = ride.toMap();
      expect(map['vehicleType'], equals('rikshaw'));

      final parsed = RideModel.fromMap(map);
      expect(parsed.vehicleType, equals('rikshaw'));
      expect(parsed.status, equals(RideStatus.requested));
    });

    test('defaults to car if vehicleType is omitted in database map', () {
      final map = {
        'id': 'ride_old',
        'riderId': 'rider_xyz',
        'status': 'requested',
        'pickup': {'latitude': 31.27, 'longitude': 72.33, 'address': 'Pickup'},
        'dropoff': {'latitude': 31.29, 'longitude': 72.35, 'address': 'Dropoff'},
        'offeredFare': 150.0,
        'suggestedFare': 150.0,
        'distanceKm': 5.0,
        'durationMin': 15.0,
        'pin': '1111',
        'createdAt': DateTime.now().toIso8601String(),
      };

      final parsed = RideModel.fromMap(map);
      expect(parsed.vehicleType, equals('car'));
    });
  });

  group('PricingMLService Multi-Vehicle Fares', () {
    test('computeFaresForAllVehicles returns map for car, bike, and rikshaw', () async {
      final pricing = PricingMLService();
      final fares = await pricing.computeFaresForAllVehicles(distanceKm: 8.0);

      expect(fares.containsKey(VehicleType.car), isTrue);
      expect(fares.containsKey(VehicleType.bike), isTrue);
      expect(fares.containsKey(VehicleType.rikshaw), isTrue);

      final carFare = fares[VehicleType.car]!;
      final bikeFare = fares[VehicleType.bike]!;
      final rikshawFare = fares[VehicleType.rikshaw]!;

      expect(carFare, greaterThanOrEqualTo(VehicleType.car.minFare));
      expect(bikeFare, lessThan(carFare));
      expect(rikshawFare, lessThan(carFare));
      expect(bikeFare, lessThanOrEqualTo(rikshawFare));
    });
  });

  group('RiderViewModel Vehicle Selection and Calling', () {
    test('default vehicle is car and switching updates selection and fare', () {
      final vm = RiderViewModel();
      expect(vm.selectedVehicleType, equals(VehicleType.car));

      vm.selectVehicleType(VehicleType.bike);
      expect(vm.selectedVehicleType, equals(VehicleType.bike));
      expect(vm.fareController.text.isNotEmpty, isTrue);

      vm.selectVehicleType(VehicleType.rikshaw);
      expect(vm.selectedVehicleType, equals(VehicleType.rikshaw));
    });

    test('callDriver and sendDriverSms validate empty phone number safely', () async {
      final vm = RiderViewModel();

      final dialEmpty = await vm.callDriver('');
      expect(dialEmpty, isFalse);

      final dialWhitespace = await vm.callDriver('   ');
      expect(dialWhitespace, isFalse);

      final smsEmpty = await vm.sendDriverSms(phone: '');
      expect(smsEmpty, isFalse);

      // Non-empty phone number initiates dialer / sms safely
      final dialValid = await vm.callDriver('+92 300 1234567');
      expect(dialValid, isTrue);

      final smsValid = await vm.sendDriverSms(phone: '03001234567', message: 'Hello');
      expect(smsValid, isTrue);
    });

    test('seat selection dynamically clamps to vehicle capacity', () {
      final vm = RiderViewModel();
      expect(vm.selectedVehicleType, equals(VehicleType.car));
      expect(vm.bookedSeats, equals(1));

      // Car allows up to 4 seats
      vm.setBookedSeats(4);
      expect(vm.bookedSeats, equals(4));

      // Attempting more than 4 clamps to 4
      vm.setBookedSeats(6);
      expect(vm.bookedSeats, equals(4));

      // Switching to Bike immediately clamps booked seats from 4 to 1
      vm.selectVehicleType(VehicleType.bike);
      expect(vm.bookedSeats, equals(1));

      // Switching to Rikshaw allows max 2 seats
      vm.selectVehicleType(VehicleType.rikshaw);
      vm.setBookedSeats(2);
      expect(vm.bookedSeats, equals(2));
      vm.setBookedSeats(3); // exceeding clamps to 2
      expect(vm.bookedSeats, equals(2));
    });
  });

  group('TripEconomics Calculations (Fuel, Maintenance, 0% Comm, Profit)', () {
    test('predicts Car fuel mileage using Google Maps route telemetry and traffic', () {
      // 1. Heavy traffic / crawl (e.g. 5 km in 30 mins = 10 km/h)
      final heavyTrafficMileage = VehicleType.car.predictMileage(
        distanceKm: 5.0,
        durationMin: 30.0,
        trafficLevel: 'HEAVY',
      );
      // Heavy congestion drops car mileage below base 10 km/L
      expect(heavyTrafficMileage, lessThan(10.0));
      expect(heavyTrafficMileage, greaterThanOrEqualTo(6.5));

      // 2. High-speed highway flow (e.g. 30 km in 25 mins = 72 km/h)
      final highwayMileage = VehicleType.car.predictMileage(
        distanceKm: 30.0,
        durationMin: 25.0,
        trafficLevel: 'NORMAL',
      );
      // Smooth cruising improves car mileage above base 10 km/L
      expect(highwayMileage, greaterThan(10.0));
      expect(highwayMileage, lessThanOrEqualTo(14.0));
    });

    test('calculates correct economics for Bike (30 km/L) and Auto Rikshaw (22 km/L)', () {
      // Bike: 30 km / 30 km/L = 1.0 Liters consumed
      final bikeEcon = TripEconomics.calculate(
        distanceKm: 30.0,
        fare: 350.0,
        vehicleType: VehicleType.bike,
      );
      expect(bikeEcon.vehicleMileageKmPerL, equals(30.0));
      expect(bikeEcon.fuelConsumedLiters, closeTo(1.0, 0.01));
      expect(bikeEcon.fuelCost, equals(285.0));
      // Maintenance: 30 * 1.5 = 45.0
      expect(bikeEcon.maintenanceCost, equals(45.0));
      // Driver net profit: 350 - (285 + 45 + 0) = 20.0
      expect(bikeEcon.driverNetProfit, equals(20.0));

      // Rikshaw: 22 km / 22 km/L = 1.0 Liters consumed
      final rikshawEcon = TripEconomics.calculate(
        distanceKm: 22.0,
        fare: 450.0,
        vehicleType: VehicleType.rikshaw,
      );
      expect(rikshawEcon.vehicleMileageKmPerL, equals(22.0));
      expect(rikshawEcon.fuelConsumedLiters, closeTo(1.0, 0.01));
      expect(rikshawEcon.fuelCost, equals(285.0));
      // Maintenance: 22 * 2.5 = 55.0
      expect(rikshawEcon.maintenanceCost, equals(55.0));
      expect(rikshawEcon.driverNetProfit, equals(110.0));
    });

    test('calculates correct economics for Car with Google Maps calibration', () {
      // Car on a 20 km trip taking 25 mins (48 km/h smooth arterial flow)
      final carEcon = TripEconomics.calculate(
        distanceKm: 20.0,
        durationMin: 25.0,
        fare: 800.0,
        vehicleType: VehicleType.car,
        trafficLevel: 'NORMAL',
      );

      expect(carEcon.isPredictedFromGoogleMaps, isTrue);
      expect(carEcon.trafficConditionNote, isNotNull);
      // With smooth speed, predicted mileage is ~11.8 km/L
      expect(carEcon.vehicleMileageKmPerL, greaterThanOrEqualTo(10.0));
      expect(carEcon.fuelCost, greaterThan(0.0));
      expect(carEcon.maintenanceCost, equals(20.0 * 4.0)); // 80 PKR
      expect(carEcon.driverNetProfit, greaterThan(0.0));
    });

    test('FuelPriceData handles live internet prices and fallback baseline', () {
      final baseline = FuelPriceData.baseline();
      expect(baseline.petrolPricePerL, equals(285.0));
      expect(baseline.isLive, isFalse);

      final liveMap = {
        'petrolPricePerL': 377.71,
        'dieselPricePerL': 391.75,
        'cngPricePerKg': 220.0,
        'source': 'OGRA Notified Prices, Government of Pakistan',
      };
      final liveData = FuelPriceData.fromMap(liveMap, isLive: true);
      expect(liveData.petrolPricePerL, equals(377.71));
      expect(liveData.dieselPricePerL, equals(391.75));
      expect(liveData.isLive, isTrue);
      expect(liveData.source, contains('OGRA'));
    });
  });
}
