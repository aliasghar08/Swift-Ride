import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/constants/app_constants.dart';
import 'package:swiftride/core/utils/distance_calculator.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_offer_model.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/presentation/common/legal_terms_modal.dart';
import 'package:swiftride/services/auth_service.dart';
import 'package:swiftride/services/pricing_ml_service.dart';

void main() {
  group('Legal Terms & Regulatory Protection Tests', () {
    testWidgets('LegalTermsModal renders all 3 tabs and non-carrier disclosure', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LegalTermsModal(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header and Tab structure
      expect(find.text('Legal & Regulatory Center'), findsOneWidget);
      expect(find.text('Terms & Status'), findsOneWidget);
      expect(find.text('2% Fee Policy'), findsOneWidget);
      expect(find.text('Privacy & PECA'), findsOneWidget);

      // Verify Non-Carrier and Independent Contractor clauses
      expect(find.text('Non-Carrier & Technology Intermediary Status'), findsOneWidget);
      expect(find.text('1. Independent Contractor Relationship'), findsOneWidget);

      // Scroll to verify subsequent clauses
      await tester.scrollUntilVisible(
        find.text('2. Assumption of Risk & Limitation of Liability'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('2. Assumption of Risk & Limitation of Liability'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('4. Dispute Resolution & Arbitration'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('4. Dispute Resolution & Arbitration'), findsOneWidget);

      // Switch to 2% Fee Policy tab
      await tester.tap(find.text('2% Fee Policy'));
      await tester.pumpAndSettle();

      expect(find.text('Permanent 2% Platform Commission Guarantee'), findsOneWidget);
      expect(find.text('1. Transparent 2% Facilitation Fee'), findsOneWidget);
      expect(find.text('2. No Hidden Surcharges or Algorithmic Skimming'), findsOneWidget);

      // Switch to Privacy & PECA tab
      await tester.tap(find.text('Privacy & PECA'));
      await tester.pumpAndSettle();

      expect(find.text('Data Protection & PECA 2016 Compliance'), findsOneWidget);
      expect(find.text('1. Geolocation Tracking Scope'), findsOneWidget);
      expect(find.text('3. Data Retention & One-Tap Account Deletion'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('4. AI Assistant & Third-Party Processing Disclosure'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('4. AI Assistant & Third-Party Processing Disclosure'), findsOneWidget);
      expect(find.textContaining('Google Play'), findsNothing);
    });

    test('AuthService.isReviewerDemoNumber recognizes all designated App Store Review demo accounts', () {
      expect(AuthService.isReviewerDemoNumber('+15550100001'), isTrue);
      expect(AuthService.isReviewerDemoNumber('+15550100002'), isTrue);
      expect(AuthService.isReviewerDemoNumber('15550100001'), isTrue);
      expect(AuthService.isReviewerDemoNumber('5550100001'), isTrue);
      expect(AuthService.isReviewerDemoNumber('+923000000000'), isTrue);
      expect(AuthService.isReviewerDemoNumber('+923000000001'), isTrue);
      expect(AuthService.isReviewerDemoNumber('+923000000002'), isTrue);
      expect(AuthService.isReviewerDemoNumber('3000000001'), isTrue);
      expect(AuthService.isReviewerDemoNumber('+923087502250'), isFalse);
      expect(AuthService.isReviewerDemoNumber(''), isFalse);
    });
  });

  group('Micro-Level Math and Edge Case Hardening Tests', () {
    test('DistanceCalculator.calculateSuggestedFare defends against negative and NaN inputs', () {
      // Normal calculation
      final fare1 = DistanceCalculator.calculateSuggestedFare(5.0, 10.0);
      expect(fare1, greaterThanOrEqualTo(AppConstants.baseFare));

      // Negative distance and duration floor to base fare
      final fareNeg = DistanceCalculator.calculateSuggestedFare(-10.0, -5.0);
      expect(fareNeg, equals(AppConstants.baseFare));

      // NaN inputs floor to base fare safely without throwing
      final fareNan = DistanceCalculator.calculateSuggestedFare(double.nan, double.nan);
      expect(fareNan, equals(AppConstants.baseFare));

      // Infinite inputs floor to base fare safely
      final fareInf = DistanceCalculator.calculateSuggestedFare(double.infinity, double.negativeInfinity);
      expect(fareInf, equals(AppConstants.baseFare));
    });

    test('DistanceCalculator.calculateZeroCommissionSavings defends against NaN and negative values', () {
      final savingsNormal = DistanceCalculator.calculateZeroCommissionSavings(1000.0);
      expect(savingsNormal, equals(110.0)); // 11% savings vs 13% incumbent

      expect(DistanceCalculator.calculateZeroCommissionSavings(-500.0), equals(0.0));
      expect(DistanceCalculator.calculateZeroCommissionSavings(double.nan), equals(0.0));
      expect(DistanceCalculator.calculateZeroCommissionSavings(double.infinity), equals(0.0));
    });

    test('PricingMLService.predictSuggestedBid handles NaN and extreme values cleanly', () async {
      final service = PricingMLService();

      // Passing NaN or negative distance should gracefully fall back to safe minimum
      final bid1 = await service.predictSuggestedBid(
        distanceKm: double.nan,
        timeOfDayHours: double.nan,
        isRaining: double.nan,
        trafficMultiplier: double.nan,
        vehicleType: VehicleType.car,
      );
      expect(bid1, greaterThanOrEqualTo(120.0));
      expect(bid1.isNaN, isFalse);
      expect(bid1.isInfinite, isFalse);

      // Negative values
      final bidNeg = await service.predictSuggestedBid(
        distanceKm: -5.0,
        timeOfDayHours: -1.0,
        vehicleType: VehicleType.bike,
      );
      expect(bidNeg, greaterThanOrEqualTo(70.0));
      expect(bidNeg.isNaN, isFalse);
    });

    test('RideModel.fromMap cleanly parses mismatched types without throwing', () {
      final mapWithNumbers = {
        'id': 9999,
        'riderId': 12345,
        'pin': 5949, // Numeric pin
        'status': 'REQUESTED',
        'offeredFare': '250',
        'suggestedFare': 250,
        'distanceKm': 4.5,
        'durationMin': 12.0,
      };

      final ride = RideModel.fromMap(mapWithNumbers);
      expect(ride.pin, equals('5949'));
      expect(ride.id, equals('9999'));
      expect(ride.riderId, equals('12345'));
    });

    test('RideOffer.fromMap cleanly parses numeric IDs and fields', () {
      final mapWithNumbers = {
        'id': 1001,
        'rideId': 2002,
        'driverId': 3003,
        'driverName': 'Muhammad Ali',
        'counterFare': 350,
        'etaMinutes': 4,
        'status': 'PENDING',
      };

      final offer = RideOffer.fromMap(mapWithNumbers);
      expect(offer.id, equals('1001'));
      expect(offer.rideId, equals('2002'));
      expect(offer.driverId, equals('3003'));
      expect(offer.driverName, equals('Muhammad Ali'));
    });

    test('DriverProfile.fromMap defaults unlocated driver to 0.0, 0.0 instead of Islamabad', () {
      final map = {
        'userId': 'driver_123',
        'licenseNumber': 'PK-12345',
        'isVerified': true,
        'isOnline': false,
      };

      final profile = DriverProfile.fromMap(map);
      expect(profile.latitude, equals(0.0));
      expect(profile.longitude, equals(0.0));
    });
  });
}
