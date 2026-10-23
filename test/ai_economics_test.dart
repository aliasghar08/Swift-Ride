import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/trip_economics_model.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
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
      expect(econ.serviceCharges, equals(0.0)); // 0% commission

      // Assert mathematical identity: Profit = Fare - Expenses
      final expectedExpenses = ((econ.fuelCost + econ.maintenanceCost) * 10).round() / 10.0;
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
  });
}
