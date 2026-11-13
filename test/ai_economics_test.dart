import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/trip_economics_model.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
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
  });
}
