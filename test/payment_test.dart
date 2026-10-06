import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/payment_rail.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';

void main() {
  // RiderViewModel touches platform channels (storage/notifications).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaymentRail', () {
    test('only cash is configured', () {
      final configured = PaymentRail.values.where((r) => r.isConfigured).toList();

      // Guard against re-adding an option with no integration behind it. The
      // picker used to offer Stripe, Apple Pay and Google Pay, none of which
      // could ever complete a payment — and Stripe cannot onboard a
      // Pakistan-based entity at all.
      expect(configured, [PaymentRail.cash]);
    });

    test('every rail has a stable id and a visible label', () {
      final ids = PaymentRail.values.map((r) => r.id).toSet();
      expect(ids.length, PaymentRail.values.length, reason: 'ids must be unique');

      for (final rail in PaymentRail.values) {
        expect(rail.id, isNotEmpty);
        expect(rail.label, isNotEmpty);
        expect(rail.description, isNotEmpty);
      }
    });

    test('fromId round-trips and falls back safely', () {
      for (final rail in PaymentRail.values) {
        expect(PaymentRail.fromId(rail.id), rail);
      }

      // An unknown or absent method must not leave the rider without a way to pay.
      expect(PaymentRail.fromId(null), PaymentRail.cash);
      expect(PaymentRail.fromId('bitcoin'), PaymentRail.cash);
    });

    test('the market rails are declared even though they are not live', () {
      final ids = PaymentRail.values.map((r) => r.id).toList();

      // These are the rails SwiftRide intends to support in Pakistan; they are
      // visible-but-disabled rather than absent, so the gap is honest.
      expect(ids, containsAll(['jazzcash', 'easypaisa', 'raast']));
    });
  });

  group('RiderViewModel payment selection', () {
    test('defaults to cash', () {
      final vm = RiderViewModel();
      expect(vm.selectedRail, PaymentRail.cash);
      expect(vm.selectedPaymentMethod, 'Cash to Driver');
      vm.dispose();
    });

    test('refuses to select a rail that is not configured', () {
      final vm = RiderViewModel();

      vm.selectPaymentMethod(PaymentRail.card);
      expect(vm.selectedRail, PaymentRail.cash);

      vm.selectPaymentMethod(PaymentRail.jazzcash);
      expect(vm.selectedRail, PaymentRail.cash);

      // A configured rail still works.
      vm.selectPaymentMethod(PaymentRail.cash);
      expect(vm.selectedRail, PaymentRail.cash);

      vm.dispose();
    });
  });

  group('RideModel payment fields', () {
    test('paymentMethod round-trips through toMap/fromMap', () {
      final ride = RideModel(
        id: 'ride_pay',
        riderId: 'rider_1',
        pickup: const LocationPoint(latitude: 33.70, longitude: 73.05, address: 'A'),
        dropoff: const LocationPoint(latitude: 33.56, longitude: 72.85, address: 'B'),
        offeredFare: 500,
        suggestedFare: 520,
        distanceKm: 5.2,
        durationMin: 12,
        pin: '4321',
        paymentMethod: PaymentRail.cash.id,
        createdAt: DateTime.now(),
      );

      final restored = RideModel.fromMap(ride.toMap(), docId: 'ride_pay');

      expect(restored.paymentMethod, 'cash');
      expect(restored.paymentStatus, 'pending');
    });

    test('an unpaid trip is never reported as paid', () {
      final ride = RideModel(
        id: 'ride_unpaid',
        riderId: 'rider_1',
        pickup: const LocationPoint(latitude: 33.70, longitude: 73.05, address: 'A'),
        dropoff: const LocationPoint(latitude: 33.56, longitude: 72.85, address: 'B'),
        offeredFare: 500,
        suggestedFare: 520,
        distanceKm: 5.2,
        durationMin: 12,
        pin: '4321',
        createdAt: DateTime.now(),
      );

      expect(ride.paymentStatus, isNot('paid'));
      expect(ride.paymentMethod, isNull, reason: 'rider has not chosen yet');
    });
  });
}
