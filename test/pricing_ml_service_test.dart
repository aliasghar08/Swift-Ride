import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/services/pricing_ml_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PricingMLService Tests (inDrive Pakistan Calibrated)', () {
    final service = PricingMLService();

    test('1. Short distance calculation returns realistic inDrive Pakistan bid', () async {
      final bid = await service.predictSuggestedBid(
        distanceKm: 3.5,
        timeOfDayHours: 10.0,
        isRaining: 0.0,
        trafficMultiplier: 1.1,
      );
      // Realistic short trip fare in Pakistan (covers petrol, wear, wage)
      expect(bid, greaterThanOrEqualTo(200.0));
      expect(bid, lessThanOrEqualTo(650.0));
      // Ensures rounding to nearest PKR 5
      expect(bid % 5.0, equals(0.0));
    });

    test('2. Long distance trip scales fare appropriately', () async {
      final shortBid = await service.predictSuggestedBid(
        distanceKm: 4.0,
        timeOfDayHours: 14.0,
        trafficMultiplier: 1.1,
      );
      final longBid = await service.predictSuggestedBid(
        distanceKm: 30.0,
        timeOfDayHours: 14.0,
        trafficMultiplier: 1.1,
      );
      expect(longBid, greaterThan(shortBid * 3.0));
      expect(longBid % 5.0, equals(0.0));
    });

    test('3. Rain and peak traffic multipliers increase sweet-spot bid', () async {
      final clearBid = await service.predictSuggestedBid(
        distanceKm: 8.0,
        timeOfDayHours: 12.0,
        isRaining: 0.0,
        trafficMultiplier: 1.0,
      );
      final rainTrafficBid = await service.predictSuggestedBid(
        distanceKm: 8.0,
        timeOfDayHours: 18.0,
        isRaining: 1.0,
        trafficMultiplier: 1.45,
      );
      expect(rainTrafficBid, greaterThan(clearBid));
      expect(rainTrafficBid % 5.0, equals(0.0));
    });

    test('4. Car model and fuel economy calibration (Alto vs Corolla)', () async {
      final altoBid = await service.predictSuggestedBid(
        distanceKm: 12.0,
        vehicleType: VehicleType.car,
        carModel: 'Suzuki Alto',
        fuelAverageKmPerL: 16.0,
      );

      final corollaBid = await service.predictSuggestedBid(
        distanceKm: 12.0,
        vehicleType: VehicleType.car,
        carModel: 'Toyota Corolla',
        fuelAverageKmPerL: 9.5,
      );

      // Sedan with heavier fuel consumption commands higher fare
      expect(corollaBid, greaterThan(altoBid));
      expect(corollaBid % 5.0, equals(0.0));
      expect(altoBid % 5.0, equals(0.0));
    });
  });
}
