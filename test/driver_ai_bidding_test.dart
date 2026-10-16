import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';
import 'package:swiftride/services/pricing_ml_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Driver AI Bidding & Counter-Offer Assistant Tests', () {
    late DriverViewModel viewModel;

    setUp(() {
      viewModel = DriverViewModel(
        pricingMLService: PricingMLService(),
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('1. Predicts and caches AI market valuation for incoming ride request', () async {
      final ride = RideModel(
        id: 'ride-jhang-01',
        riderId: 'rider-123',
        pickup: LocationPoint(latitude: 31.2785, longitude: 72.3317, address: 'Shaheed Chowk, Jhang'),
        dropoff: LocationPoint(latitude: 31.2900, longitude: 72.3500, address: 'District Courts, Jhang'),
        offeredFare: 150.0,
        distanceKm: 4.5,
        durationMin: 12.0,
        suggestedFare: 160.0,
        pin: '1234',
        createdAt: DateTime(2026, 10, 16),
      );

      final fare = await viewModel.getOrCalculateAiValuation(ride);
      expect(fare, greaterThanOrEqualTo(60.0));
      expect(fare % 5.0, equals(0.0)); // Rounded to nearest PKR 5

      // Cached query should return same value synchronously
      final cached = viewModel.getCachedAiValuation('ride-jhang-01');
      expect(cached, equals(fare));
    });

    test('2. Correctly flags significantly low bids with counter-offer guidance', () {
      final analysis = viewModel.analyzeFare(
        offeredFare: 100.0,
        aiValuation: 160.0, // Rider is ~37.5% below market
      );

      expect(analysis.isSignificantlyLow, isTrue);
      expect(analysis.isLow, isTrue);
      expect(analysis.tagMessage, contains('low - Counter-offer recommended'));
      expect(analysis.tagMessage, contains('PKR 160'));
    });

    test('3. Correctly flags fair bids around market sweet spot', () {
      final analysis = viewModel.analyzeFare(
        offeredFare: 160.0,
        aiValuation: 160.0,
      );

      expect(analysis.isFair, isTrue);
      expect(analysis.isLow, isFalse);
      expect(analysis.tagMessage, contains('Fair Market Offer'));
    });

    test('4. Auto-accept toggle controls threshold-based acceptance', () {
      expect(viewModel.autoAcceptAiValuedRides, isFalse);

      // When toggle is OFF, should never auto-accept
      expect(
        viewModel.shouldAutoAccept(offeredFare: 160.0, aiValuation: 160.0),
        isFalse,
      );

      // Turn toggle ON
      viewModel.toggleAutoAcceptAiValuedRides(true);
      expect(viewModel.autoAcceptAiValuedRides, isTrue);

      // Exact match (0% diff) -> true
      expect(
        viewModel.shouldAutoAccept(offeredFare: 160.0, aiValuation: 160.0),
        isTrue,
      );

      // Within -5% (PKR 155 vs PKR 160 = -3.1%) -> true
      expect(
        viewModel.shouldAutoAccept(offeredFare: 155.0, aiValuation: 160.0),
        isTrue,
      );

      // Higher than market (PKR 200 vs PKR 160) -> true
      expect(
        viewModel.shouldAutoAccept(offeredFare: 200.0, aiValuation: 160.0),
        isTrue,
      );

      // Significantly lower than market (PKR 120 vs PKR 160 = -25%) -> false
      expect(
        viewModel.shouldAutoAccept(offeredFare: 120.0, aiValuation: 160.0),
        isFalse,
      );
    });
  });
}
