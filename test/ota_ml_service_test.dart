import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/ai/ml/pricing_ml_service.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';

void main() {
  group('OTA Dynamic ML Model Loading & Fallback', () {
    test('PricingMLService default version and properties', () {
      final service = PricingMLService();
      expect(service.activeModelVersion, 'bundled_v1');
      expect(service.isUsingOtaModel, isFalse);
    });

    test('PricingMLService loadOtaModel gracefully handles missing files', () async {
      final service = PricingMLService();
      final loaded = await service.loadOtaModel(
        modelFilePath: '/non_existent_path/fake_model.tflite',
        manifest: {'version': 'ota_v20261122'},
      );

      // Should return false and not crash
      expect(loaded, isFalse);
      expect(service.activeModelVersion, 'bundled_v1');
      expect(service.isUsingOtaModel, isFalse);
    });

    test('PricingMLService predictive economics inference works with algorithmic fallback', () async {
      final service = PricingMLService();

      final economics = await service.predictTripEconomics(
        distanceKm: 10.0,
        durationMin: 20,
        vehicleType: VehicleType.car,
        bookedSeats: 1,
        fuelPrice: 285.0,
        carModel: 'Suzuki Alto',
        roadCondition: 1,
        acEnabled: true,
      );

      expect(economics.fuelConsumedLiters, greaterThan(0.2));
      expect(economics.maintenanceCost, greaterThan(10.0));
      expect(economics.totalFare, greaterThan(200.0));
      expect(economics.driverNetProfit, greaterThan(50.0));
    });
  });
}
