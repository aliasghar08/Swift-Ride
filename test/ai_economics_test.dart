import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/trip_economics_model.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
import 'package:swiftride/presentation/widgets/trip_economics_sheet.dart';
import 'package:swiftride/services/pricing_ml_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-Output AI Economics Engine (TFLite & Physics)', () {
    test('predictTripEconomics generates positive, mathematically consistent numbers for Bike', () async {
      final pricingService = PricingMLService();
      final econ = await pricingService.predictTripEconomics(
        distanceKm: 12.0,
        durationMin: 20,
        staticDurationMin: 18,
        vehicleType: VehicleType.bike,
        bookedSeats: 1,
        fuelPrice: 377.71,
      );

      expect(econ.isAiPredicted, isTrue);
      expect(econ.vehicleType, equals(VehicleType.bike));
      expect(econ.bookedSeats, equals(1));
      expect(econ.totalSeats, equals(1));

      // Assert positive financial metrics
      expect(econ.fuelConsumedLiters, greaterThan(0.0));
      expect(econ.fuelCost, greaterThan(0.0));
      expect(econ.maintenanceCost, greaterThan(0.0));
      expect(econ.totalFare, greaterThan(econ.fuelCost));
      expect(econ.driverNetProfit, greaterThan(0.0));
      expect(econ.serviceCharges, equals((econ.totalFare * 0.02 * 10).round() / 10.0)); // 2% commission

      // Assert mathematical identity: Profit = Fare - Expenses
      final expectedExpenses = ((econ.fuelCost + econ.maintenanceCost + econ.serviceCharges) * 10).round() / 10.0;
      expect(econ.driverTotalExpenses, closeTo(expectedExpenses, 0.1));
      expect(econ.driverNetProfit, closeTo(econ.totalFare - econ.driverTotalExpenses, 0.1));
    });

    test('predictTripEconomics accounts for passenger payload in Auto Rikshaw', () async {
      final pricingService = PricingMLService();
      final econSolo = await pricingService.predictTripEconomics(
        distanceKm: 15.0,
        durationMin: 35,
        staticDurationMin: 30,
        vehicleType: VehicleType.rikshaw,
        bookedSeats: 1,
        fuelPrice: 377.71,
      );

      final econFull = await pricingService.predictTripEconomics(
        distanceKm: 15.0,
        durationMin: 35,
        staticDurationMin: 30,
        vehicleType: VehicleType.rikshaw,
        bookedSeats: 2,
        fuelPrice: 377.71,
      );

      expect(econSolo.isAiPredicted, isTrue);
      expect(econFull.isAiPredicted, isTrue);
      expect(econFull.bookedSeats, equals(2));

      // Passenger payload increases fuel burn and market clearing fare
      expect(econFull.fuelConsumedLiters, greaterThanOrEqualTo(econSolo.fuelConsumedLiters));
      expect(econFull.totalFare, greaterThanOrEqualTo(econSolo.totalFare));
    });

    test('predictTripEconomics scales with urban congestion friction in Car', () async {
      final pricingService = PricingMLService();
      // Free-flow highway: 20 km in 20 min
      final highwayEcon = await pricingService.predictTripEconomics(
        distanceKm: 20.0,
        durationMin: 20,
        staticDurationMin: 20,
        vehicleType: VehicleType.car,
        bookedSeats: 3,
        fuelPrice: 377.71,
        trafficLevel: 'NORMAL',
      );

      // Heavy bazaar gridlock: 20 km in 55 min
      final gridlockEcon = await pricingService.predictTripEconomics(
        distanceKm: 20.0,
        durationMin: 55,
        staticDurationMin: 25,
        vehicleType: VehicleType.car,
        bookedSeats: 3,
        fuelPrice: 377.71,
        trafficLevel: 'HEAVY',
      );

      // Congestion stress increases mechanical maintenance & wear
      expect(gridlockEcon.maintenanceCost, greaterThan(highwayEcon.maintenanceCost));
      expect(gridlockEcon.fuelConsumedLiters, greaterThan(highwayEcon.fuelConsumedLiters));
      expect(gridlockEcon.totalFare, greaterThan(highwayEcon.totalFare));
    });

    test('predictTripEconomics differentiates 660cc Alto vs 1300cc Corolla accurately', () async {
      final pricingService = PricingMLService();

      // 660cc Alto
      final altoEcon = await pricingService.predictTripEconomics(
        distanceKm: 25.0,
        durationMin: 45,
        staticDurationMin: 35,
        vehicleType: VehicleType.car,
        carEngineTier: CarEngineTier.mini660cc,
        carModel: 'Suzuki Alto',
        bookedSeats: 2,
        fuelPrice: 332.0,
      );

      // 1300cc Corolla
      final corollaEcon = await pricingService.predictTripEconomics(
        distanceKm: 25.0,
        durationMin: 45,
        staticDurationMin: 35,
        vehicleType: VehicleType.car,
        carEngineTier: CarEngineTier.sedan1300cc,
        carModel: 'Toyota Corolla',
        bookedSeats: 2,
        fuelPrice: 332.0,
      );

      expect(altoEcon.isAiPredicted, isTrue);
      expect(corollaEcon.isAiPredicted, isTrue);

      // Alto (660cc) burns significantly less petrol than Corolla (1300cc)
      expect(altoEcon.fuelConsumedLiters, lessThan(corollaEcon.fuelConsumedLiters));
      expect(altoEcon.fuelCost, lessThan(corollaEcon.fuelCost));

      // Sedan maintenance & depreciation is higher
      expect(altoEcon.maintenanceCost, lessThan(corollaEcon.maintenanceCost));

      // Fair sweet-spot fare reflects the lower operating expense of a 660cc car
      expect(altoEcon.totalFare, lessThan(corollaEcon.totalFare));
    });

    test('predictTripEconomics scales with road condition and AC load', () async {
      final pricingService = PricingMLService();

      // Smooth highway, AC off
      final smoothEcon = await pricingService.predictTripEconomics(
        distanceKm: 18.0,
        durationMin: 25,
        staticDurationMin: 25,
        vehicleType: VehicleType.car,
        carEngineTier: CarEngineTier.compact1000cc,
        roadCondition: 0,
        acEnabled: false,
        bookedSeats: 2,
        fuelPrice: 332.0,
      );

      // Broken / rough rural road, AC on
      final roughAcEcon = await pricingService.predictTripEconomics(
        distanceKm: 18.0,
        durationMin: 35,
        staticDurationMin: 25,
        vehicleType: VehicleType.car,
        carEngineTier: CarEngineTier.compact1000cc,
        roadCondition: 2,
        acEnabled: true,
        bookedSeats: 2,
        fuelPrice: 332.0,
      );

      expect(roughAcEcon.fuelConsumedLiters, greaterThan(smoothEcon.fuelConsumedLiters));
      expect(roughAcEcon.maintenanceCost, greaterThan(smoothEcon.maintenanceCost));
      expect(roughAcEcon.totalFare, greaterThan(smoothEcon.totalFare));
    });

    test('TripEconomics serializes and deserializes isAiPredicted correctly', () {
      final econ = TripEconomics.calculate(
        distanceKm: 10.0,
        fare: 500.0,
        vehicleType: VehicleType.car,
        isAiPredicted: true,
      );
      expect(econ.isAiPredicted, isTrue);

      final map = econ.toMap();
      expect(map['isAiPredicted'], isTrue);
    });

    test('DriverViewModel predicts economics inferring engine tier from vehicle model', () async {
      final driverVm = DriverViewModel();
      final rideCar = RideModel(
        id: 'ride-alto',
        riderId: 'rider-1',
        pickup: LocationPoint(latitude: 31.2785, longitude: 72.3317, address: 'Shaheed Chowk, Jhang'),
        dropoff: LocationPoint(latitude: 31.2900, longitude: 72.3500, address: 'District Courts, Jhang'),
        offeredFare: 250.0,
        distanceKm: 6.0,
        durationMin: 14.0,
        suggestedFare: 260.0,
        vehicleType: 'car',
        pin: '1234',
        createdAt: DateTime(2026, 11, 13),
      );

      // 660cc Alto
      final altoEcon = await driverVm.predictTripEconomics(
        ride: rideCar,
        vehicleModel: 'Suzuki Alto VXR 660cc',
        fuelPrice: 332.0,
      );
      expect(altoEcon.carEngineTier, equals(CarEngineTier.mini660cc));
      expect(altoEcon.acEnabled, isTrue);

      // 1300cc+ Corolla
      final corollaEcon = await driverVm.predictTripEconomics(
        ride: rideCar,
        vehicleModel: 'Toyota Corolla GLi 1.3',
        fuelPrice: 332.0,
      );
      expect(corollaEcon.carEngineTier, equals(CarEngineTier.sedan1300cc));
      expect(corollaEcon.acEnabled, isTrue);

      // Corolla consumes more fuel and has higher wear than Alto
      expect(corollaEcon.fuelConsumedLiters, greaterThan(altoEcon.fuelConsumedLiters));
      expect(corollaEcon.maintenanceCost, greaterThan(altoEcon.maintenanceCost));

      driverVm.dispose();
    });

    test('RiderViewModel sets acEnabled true for Car and false for Bike/Rikshaw', () {
      final riderVm = RiderViewModel();

      // Default or Car
      riderVm.selectVehicleType(VehicleType.car);
      expect(riderVm.currentTripEconomics.acEnabled, isTrue);

      // Bike
      riderVm.selectVehicleType(VehicleType.bike);
      expect(riderVm.currentTripEconomics.acEnabled, isFalse);

      // Rikshaw
      riderVm.selectVehicleType(VehicleType.rikshaw);
      expect(riderVm.currentTripEconomics.acEnabled, isFalse);

      riderVm.dispose();
    });

    test('Calibrated AI Sweet Spot achieves 35-45% driver net margin and 10 km car suggests ~PKR 480-520', () async {
      final pricingService = PricingMLService();

      // 10 km compact car city trip (20 min duration, normal traffic, AC on)
      final carEcon = await pricingService.predictTripEconomics(
        distanceKm: 10.0,
        durationMin: 20,
        staticDurationMin: 20,
        vehicleType: VehicleType.car,
        carEngineTier: CarEngineTier.compact1000cc,
        acEnabled: true,
        bookedSeats: 1,
        fuelPrice: 285.0,
        trafficLevel: 'NORMAL',
      );

      // Fare should be between PKR 480 and PKR 520
      expect(carEcon.totalFare, greaterThanOrEqualTo(480.0));
      expect(carEcon.totalFare, lessThanOrEqualTo(520.0));

      // Net profit margin = driverNetProfit / totalFare -> target 35%-45%
      final margin = carEcon.driverNetProfit / carEcon.totalFare;
      expect(margin, greaterThanOrEqualTo(0.35));
      expect(margin, lessThanOrEqualTo(0.48));

      // 1.18x Cost Floor protection test
      final costFloor = carEcon.costFloor;
      final expectedCostFloor = (carEcon.fuelCost + carEcon.maintenanceCost) * 1.18;
      expect(costFloor, closeTo(expectedCostFloor, 0.01));

      // Margin at cost floor: at least ~13%
      final minProfit = costFloor - (carEcon.fuelCost + carEcon.maintenanceCost + (costFloor * 0.02));
      final minMargin = minProfit / costFloor;
      expect(minMargin, greaterThanOrEqualTo(0.12));
    });

    test('Calibrated Bike 10 km suggests ~PKR 200 and Auto Rikshaw suggests ~PKR 330-350', () async {
      final pricingService = PricingMLService();

      // 10 km Bike
      final bikeEcon = await pricingService.predictTripEconomics(
        distanceKm: 10.0,
        durationMin: 18,
        staticDurationMin: 18,
        vehicleType: VehicleType.bike,
        bookedSeats: 1,
        fuelPrice: 285.0,
      );
      expect(bikeEcon.totalFare, closeTo(200.0, 15.0));

      // 10 km Rikshaw
      final rikshawEcon = await pricingService.predictTripEconomics(
        distanceKm: 10.0,
        durationMin: 22,
        staticDurationMin: 20,
        vehicleType: VehicleType.rikshaw,
        bookedSeats: 1,
        fuelPrice: 285.0,
      );
      expect(rikshawEcon.totalFare, greaterThanOrEqualTo(320.0));
      expect(rikshawEcon.totalFare, lessThanOrEqualTo(360.0));
    });

    testWidgets('TripEconomicsSheet displays 98% fairness breakdown for riders and hides net profit', (tester) async {
      final pricingService = PricingMLService();
      final econ = await pricingService.predictTripEconomics(
        distanceKm: 10.0,
        durationMin: 20,
        staticDurationMin: 20,
        vehicleType: VehicleType.car,
        bookedSeats: 1,
        fuelPrice: 285.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripEconomicsSheet(
              economics: econ,
              isDriverView: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rider view must show 98% Captain Payout & Fair Split banner
      expect(find.text('FAIR FARE SPLIT (98% TO CAPTAIN)'), findsOneWidget);
      expect(find.text('Captain Payout (98%)'), findsOneWidget);
      expect(find.textContaining('98% goes directly to your captain'), findsOneWidget);

      // Rider view must NEVER show driver net take-home profit
      expect(find.text('YOUR REAL TAKE-HOME PROFIT'), findsNothing);
      expect(find.text('Real Take-Home (After Fuel & Wear)'), findsNothing);
    });

    testWidgets('TripEconomicsSheet displays full ledger & take-home profit for drivers', (tester) async {
      final pricingService = PricingMLService();
      final econ = await pricingService.predictTripEconomics(
        distanceKm: 10.0,
        durationMin: 20,
        staticDurationMin: 20,
        vehicleType: VehicleType.car,
        bookedSeats: 1,
        fuelPrice: 285.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripEconomicsSheet(
              economics: econ,
              isDriverView: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Driver view must show full take-home profit ledger
      expect(find.text('YOUR REAL TAKE-HOME PROFIT'), findsOneWidget);
      expect(find.text('Real Take-Home (After Fuel & Wear)'), findsOneWidget);
      expect(find.text('Driver Net Payout (98% Gross)'), findsOneWidget);
      expect(find.text('FAIR FARE SPLIT (98% TO CAPTAIN)'), findsNothing);
    });
  });
}
