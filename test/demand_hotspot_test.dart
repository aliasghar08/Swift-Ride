import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/demand_hotspot_model.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DemandHotspot Model & Repositioning Nudges', () {
    test('DemandHotspot model serialization and distance computation', () {
      final now = DateTime.now();
      final hotspot = DemandHotspot(
        cellId: 'w28s4m',
        lat: 31.5204,
        lng: 74.3587,
        demandScore: 0.85,
        surgeMultiplier: 1.8,
        requestCount: 14,
        driverCount: 2,
        radiusM: 650.0,
        updatedAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
      );

      expect(hotspot.isHighDemand, isTrue);
      expect(hotspot.isModerateDemand, isFalse);
      expect(hotspot.isExpired, isFalse);

      // Distance to nearby coordinate (~2.5 km away)
      final dist = hotspot.distanceToKm(31.5400, 74.3587);
      expect(dist, greaterThan(1.5));
      expect(dist, lessThan(3.5));

      final map = hotspot.toMap();
      expect(map['cellId'], 'w28s4m');
      expect(map['demandScore'], 0.85);

      final reconstructed = DemandHotspot.fromMap(map, docId: 'w28s4m');
      expect(reconstructed.cellId, 'w28s4m');
      expect(reconstructed.demandScore, 0.85);
      expect(reconstructed.surgeMultiplier, 1.8);
    });

    test('DriverViewModel evaluateRepositioningNudge triggers in cold zone with nearby hotspot', () {
      final viewModel = DriverViewModel();
      final now = DateTime.now();

      final highDemandHotspot = DemandHotspot(
        cellId: 'gulberg_high',
        lat: 31.5150,
        lng: 74.3450,
        demandScore: 0.82,
        surgeMultiplier: 1.6,
        requestCount: 18,
        driverCount: 1,
        updatedAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
      );

      viewModel.setDemandHotspots([highDemandHotspot]);

      // 1. Not online -> No nudge
      viewModel.evaluateRepositioningNudge(
        currentLat: 31.5300,
        currentLng: 74.3450,
        isOnline: false,
        idleDuration: const Duration(minutes: 15),
      );
      expect(viewModel.repositioningNudge, isNull);

      // 2. Online but not idle enough (< 10 min) -> No nudge
      viewModel.evaluateRepositioningNudge(
        currentLat: 31.5300,
        currentLng: 74.3450,
        isOnline: true,
        idleDuration: const Duration(minutes: 5),
      );
      expect(viewModel.repositioningNudge, isNull);

      // 3. Online, idle >= 10 min, ~1.7 km from hotspot (cold zone) -> Nudge triggers!
      viewModel.evaluateRepositioningNudge(
        currentLat: 31.5300,
        currentLng: 74.3450,
        isOnline: true,
        idleDuration: const Duration(minutes: 12),
      );
      expect(viewModel.repositioningNudge, isNotNull);
      expect(viewModel.repositioningNudge, contains('High demand nearby'));
      expect(viewModel.targetHotspot?.cellId, 'gulberg_high');

      // 4. Dismiss nudge
      viewModel.dismissRepositioningNudge();
      expect(viewModel.repositioningNudge, isNull);
      expect(viewModel.targetHotspot, isNull);
    });

    test('Hotspots toggle flips showHotspots correctly', () {
      final viewModel = DriverViewModel();
      expect(viewModel.showHotspots, isTrue);

      viewModel.toggleHotspots();
      expect(viewModel.showHotspots, isFalse);

      viewModel.toggleHotspots();
      expect(viewModel.showHotspots, isTrue);
    });
  });
}
