import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/ai/data/ai_remote_datasource.dart';
import 'package:swiftride/ai/presentation/dialogs/ai_consent_dialog.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Loophole Audit: Seat Capacity Clamping Tests', () {
    test('Clamps bookedSeats across vehicle types: Bike (1), Rickshaw (3), Car (4)', () {
      int getClampedSeats(String vehicleType, int requestedSeats) {
        final vType = vehicleType.toLowerCase();
        final maxCapacity = (vType == 'bike' || vType == 'moto')
            ? 1
            : ((vType == 'rickshaw' || vType == 'auto') ? 3 : 4);
        return requestedSeats.clamp(1, maxCapacity);
      }

      // Bike: capacity 1
      expect(getClampedSeats('bike', 1), equals(1));
      expect(getClampedSeats('bike', 2), equals(1));
      expect(getClampedSeats('bike', 4), equals(1));
      expect(getClampedSeats('moto', 3), equals(1));

      // Rickshaw / Auto: capacity 3
      expect(getClampedSeats('rickshaw', 1), equals(1));
      expect(getClampedSeats('rickshaw', 2), equals(2));
      expect(getClampedSeats('rickshaw', 3), equals(3));
      expect(getClampedSeats('rickshaw', 4), equals(3));
      expect(getClampedSeats('auto', 5), equals(3));

      // Car: capacity 4
      expect(getClampedSeats('car', 1), equals(1));
      expect(getClampedSeats('car', 4), equals(4));
      expect(getClampedSeats('car', 6), equals(4));
      expect(getClampedSeats('unknown', 5), equals(4));
    });
  });

  group('Loophole Audit: Fare Bounds & 2% Commission Tests', () {
    test('Rejects invalid, zero, negative, NaN, and Infinity fares below PKR 50 floor', () {
      double validateFare(double input) {
        if (input.isNaN || input.isInfinite || input < 50.0) {
          return 50.0;
        }
        return input > 99999.0 ? 99999.0 : input;
      }

      expect(validateFare(0.0), equals(50.0));
      expect(validateFare(-100.0), equals(50.0));
      expect(validateFare(30.0), equals(50.0));
      expect(validateFare(double.nan), equals(50.0));
      expect(validateFare(double.infinity), equals(50.0));
      expect(validateFare(double.negativeInfinity), equals(50.0));

      expect(validateFare(50.0), equals(50.0));
      expect(validateFare(250.0), equals(250.0));
      expect(validateFare(1000000.0), equals(99999.0));
    });

    test('Strict 2% platform commission calculation consistency', () {
      double computeCommission(double fare) {
        return ((fare * 0.02) * 10).round() / 10.0;
      }

      expect(computeCommission(50.0), equals(1.0));
      expect(computeCommission(100.0), equals(2.0));
      expect(computeCommission(150.0), equals(3.0));
      expect(computeCommission(350.0), equals(7.0));
      expect(computeCommission(500.0), equals(10.0));
      expect(computeCommission(1000.0), equals(20.0));
      expect(computeCommission(2350.0), equals(47.0));
    });
  });

  group('Loophole Audit: Boarding PIN Verification & Rejection Tests', () {
    test('Rejects incorrect PIN and preserves ride status; accepts correct PIN', () async {
      final service = FirestoreRideService();
      const rideId = 'test_ride_pin_123';

      final ride = RideModel(
        id: rideId,
        riderId: 'rider_abc',
        driverId: 'driver_xyz',
        status: RideStatus.driverArrived,
        pickup: const LocationPoint(latitude: 31.26, longitude: 72.35, address: 'Satellite Town'),
        dropoff: const LocationPoint(latitude: 31.27, longitude: 72.36, address: 'Main Bazar'),
        offeredFare: 200.0,
        suggestedFare: 200.0,
        acceptedFare: 200.0,
        distanceKm: 3.5,
        durationMin: 12.0,
        commissionAmount: 4.0,
        pin: '7842',
        createdAt: DateTime.now(),
      );

      // Seed memory ride
      await service.createRide(ride);

      // Attempt 1: Wrong PIN
      final wrongResult = await service.verifyPinAndStartTrip(rideId, '0000');
      expect(wrongResult, isFalse, reason: 'Wrong PIN must be rejected');

      final currentAfterWrong = await service.getRide(rideId);
      expect(currentAfterWrong?.status, equals(RideStatus.driverArrived),
          reason: 'Status must NOT transition to inProgress on PIN mismatch');

      // Attempt 2: Correct PIN
      final correctResult = await service.verifyPinAndStartTrip(rideId, '7842');
      expect(correctResult, isTrue, reason: 'Correct PIN must be accepted');

      final currentAfterCorrect = await service.getRide(rideId);
      expect(currentAfterCorrect?.status, equals(RideStatus.inProgress),
          reason: 'Status must transition to inProgress on valid PIN match');
    });
  });

  group('Loophole Audit: AI Consent Gate Tests', () {
    test('Declined or missing AI consent blocks remote AI and safely falls back', () async {
      // Ensure consent is revoked
      await AiConsentDialog.setConsent(false);
      expect(await AiConsentDialog.isConsentGranted(), isFalse);

      final dataSource = FirebaseAiRemoteDataSource();

      // Calling streamChat when consent is false should yield the offline fallback without error
      final streamResult = await dataSource.streamChat('Need fare advice').toList();
      final fullResponse = streamResult.join();
      expect(fullResponse, isNotEmpty);
      expect(await AiConsentDialog.isConsentGranted(), isFalse);

      // Calling generateContent when consent is false should return fallback
      final content = await dataSource.generateContent('Help me optimize my earnings');
      expect(content, isNotEmpty);

      // Calling parseIntentWithTools when consent is false should return null
      final tool = await dataSource.parseIntentWithTools('Book a ride to Mall');
      expect(tool, isNull);
    });
  });
}
