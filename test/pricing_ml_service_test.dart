import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/pricing_ml_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PricingMLService Tests', () {
    final service = PricingMLService();

    test('1. Short distance calculation returns valid bid', () async {
      final bid = await service.predictSuggestedBid(
        distanceKm: 3.5,
        timeOfDayHours: 10.0,
        isRaining: 0.0,
        trafficMultiplier: 1.1,
      );
      expect(bid, greaterThanOrEqualTo(60.0));
      expect(bid, lessThanOrEqualTo(250.0));
      // Ensures rounding to nearest PKR 5
      expect(bid % 5.0, equals(0.0));
    });

    test('2. Long distance intercity trip scales fare appropriately', () async {
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
  });
}
