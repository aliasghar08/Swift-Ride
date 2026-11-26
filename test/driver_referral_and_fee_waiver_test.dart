import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/driver_khata_model.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/ride_offer_model.dart';
import 'package:swiftride/domain/models/trip_economics_model.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/services/firestore/firestore_driver_service.dart';
import 'package:swiftride/services/referral_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriverProfile Fee Waiver & Badges', () {
    test('effectivePlatformFeeRate is 0% when waiver is active and 2% when expired or null', () {
      final now = DateTime.now();
      final activeProfile = DriverProfile.empty(userId: 'driver_123').copyWith(
        feeWaiverUntil: now.add(const Duration(days: 14)),
      );
      expect(activeProfile.isFeeWaiverActive, isTrue);
      expect(activeProfile.effectivePlatformFeeRate, equals(0.0));
      expect(activeProfile.waiverDaysRemaining, greaterThanOrEqualTo(13));

      final expiredProfile = DriverProfile.empty(userId: 'driver_123').copyWith(
        feeWaiverUntil: now.subtract(const Duration(hours: 1)),
      );
      expect(expiredProfile.isFeeWaiverActive, isFalse);
      expect(expiredProfile.effectivePlatformFeeRate, equals(0.02));
      expect(expiredProfile.waiverDaysRemaining, equals(0));

      final nullProfile = DriverProfile.empty(userId: 'driver_123');
      expect(nullProfile.isFeeWaiverActive, isFalse);
      expect(nullProfile.effectivePlatformFeeRate, equals(0.02));
      expect(nullProfile.waiverDaysRemaining, equals(0));
    });

    test('isFoundingCaptain returns true when FOUNDING_CAPTAIN badge is present', () {
      final regularDriver = DriverProfile.empty(userId: 'driver_reg').copyWith(
        badges: const ['EARLY_ADOPTER'],
      );
      expect(regularDriver.isFoundingCaptain, isFalse);

      final foundingDriver = DriverProfile.empty(userId: 'driver_founding').copyWith(
        badges: const ['FOUNDING_CAPTAIN', 'TOP_RATED'],
        verifiedReferralsCount: 5,
      );
      expect(foundingDriver.isFoundingCaptain, isTrue);
      expect(foundingDriver.verifiedReferralsCount, equals(5));
    });

    test('DriverProfile serialization preserves captain growth fields', () {
      final now = DateTime.utc(2026, 6, 1, 12, 0);
      final profile = DriverProfile.empty(userId: 'driver_456').copyWith(
        captainInviteCode: 'CAPT786',
        referredByDriverUid: 'referrer_999',
        referredByCode: 'JHANG0',
        verifiedReferralsCount: 4,
        badges: const ['FOUNDING_CAPTAIN'],
        feeWaiverUntil: now,
        weeklyCompletedRides: 12,
      );

      final map = profile.toMap();
      expect(map['captainInviteCode'], equals('CAPT786'));
      expect(map['captainReferralLink'], equals('https://swift-ride-5ab75.web.app/join?code=CAPT786'));
      expect(map['referredByDriverUid'], equals('referrer_999'));
      expect(map['referredByCode'], equals('JHANG0'));
      expect(map['verifiedReferralsCount'], equals(4));
      expect(map['badges'], equals(['FOUNDING_CAPTAIN']));
      expect(map['feeWaiverUntil'], isNotNull);
      expect(map['weeklyCompletedRides'], equals(12));

      final restored = DriverProfile.fromMap(map, docId: 'driver_456');
      expect(restored.captainInviteCode, equals('CAPT786'));
      expect(restored.referredByDriverUid, equals('referrer_999'));
      expect(restored.referredByCode, equals('JHANG0'));
      expect(restored.verifiedReferralsCount, equals(4));
      expect(restored.badges, contains('FOUNDING_CAPTAIN'));
      expect(restored.weeklyCompletedRides, equals(12));
      expect(restored.isFoundingCaptain, isTrue);
    });
  });

  group('TripEconomics 0% Fee Tier vs 2% Standard Tier', () {
    test('calculate with platformFeeRate = 0.0 charges 0 PKR platform fee', () {
      final econ = TripEconomics.calculate(
        vehicleType: VehicleType.car,
        fare: 1000.0,
        distanceKm: 10.0,
        durationMin: 20.0,
        platformFeeRate: 0.0,
      );

      expect(econ.isWaiverActive, isTrue);
      expect(econ.platformFeeRate, equals(0.0));
      expect(econ.serviceCharges, equals(0.0));
      // Driver keeps 100% of fare minus fuel & maintenance expenses
      expect(econ.driverTotalExpenses, equals(econ.fuelCost + econ.maintenanceCost));
      expect(econ.driverNetProfit, equals(1000.0 - econ.driverTotalExpenses));
    });

    test('calculate with default platformFeeRate = 0.02 charges 2% platform fee', () {
      final econ = TripEconomics.calculate(
        vehicleType: VehicleType.car,
        fare: 1000.0,
        distanceKm: 10.0,
        durationMin: 20.0,
      );

      expect(econ.isWaiverActive, isFalse);
      expect(econ.platformFeeRate, equals(0.02));
      expect(econ.serviceCharges, equals(20.0)); // 2% of 1000 PKR
      expect(econ.driverTotalExpenses, equals(econ.fuelCost + econ.maintenanceCost + 20.0));
    });
  });

  group('DriverDailyKhata 0% Fee Tier', () {
    test('retains 100% earnings with 0 commission when waiver is active', () {
      final khata = DriverDailyKhata(
        date: DateTime.now(),
        totalGrossCashCollected: 2500.0,
        totalFuelExpense: 500.0,
        totalMaintenanceReserve: 200.0,
        completedTrips: 5,
        platformFeeRate: 0.0,
      );

      expect(khata.isWaiverActive, isTrue);
      expect(khata.platformFeeRate, equals(0.0));
      expect(khata.platformCommission, equals(0.0));
      // Net cash profit = 2500 - 500 - 200 - 0 = 1800 PKR
      expect(khata.netCashProfit, equals(1800.0));
    });

    test('deducts 2% commission under standard fee tier', () {
      final khata = DriverDailyKhata(
        date: DateTime.now(),
        totalGrossCashCollected: 2500.0,
        totalFuelExpense: 500.0,
        totalMaintenanceReserve: 200.0,
        completedTrips: 5,
        platformFeeRate: 0.02,
      );

      expect(khata.isWaiverActive, isFalse);
      expect(khata.platformFeeRate, equals(0.02));
      expect(khata.platformCommission, equals(50.0)); // 2% of 2500
      // Net cash profit = 2500 - 500 - 200 - 50 = 1750 PKR
      expect(khata.netCashProfit, equals(1750.0));
    });
  });

  group('RideOffer Badges & Founding Captain', () {
    test('isFoundingCaptain reflects presence in driverBadges', () {
      final offer = RideOffer(
        id: 'offer_1',
        rideId: 'ride_1',
        driverId: 'drv_1',
        driverName: 'Captain Aslam',
        vehicleSummary: 'Honda Civic (White)',
        counterFare: 350.0,
        etaMinutes: 4,
        createdAt: DateTime.now(),
        driverBadges: const ['FOUNDING_CAPTAIN'],
      );

      expect(offer.isFoundingCaptain, isTrue);

      final map = offer.toMap();
      expect(map['driverBadges'], equals(['FOUNDING_CAPTAIN']));

      final restored = RideOffer.fromMap(map);
      expect(restored.isFoundingCaptain, isTrue);
      expect(restored.driverBadges, contains('FOUNDING_CAPTAIN'));
    });
  });

  group('FirestoreDriverService applyDriverPromoCode In-Memory Fallback', () {
    test('successfully applies official launch promo code JHANG0', () async {
      final service = FirestoreDriverService();
      final result = await service.applyDriverPromoCode('jhang0');

      expect(result['success'], isTrue);
      expect(result['feeWaiverDays'], equals(30));
      expect(result['message'], contains('0% Platform Fee Unlocked'));
    });

    test('rejects empty or whitespace code', () async {
      final service = FirestoreDriverService();
      final result = await service.applyDriverPromoCode('   ');

      expect(result['success'], isFalse);
      expect(result['message'], contains('Please enter a valid code'));
    });
  });

  group('ReferralLinkService Deep-Link & Play Install Referrer Parsing', () {
    test('parses code from custom scheme swiftride://join?code=CAPT482', () {
      final code = ReferralLinkService.parseCodeFromString('swiftride://join?code=CAPT482');
      expect(code, equals('CAPT482'));
    });

    test('parses code from Firebase Hosting web URL https://swift-ride-5ab75.web.app/join?code=CAPT786', () {
      final code = ReferralLinkService.parseCodeFromString('https://swift-ride-5ab75.web.app/join?code=CAPT786');
      expect(code, equals('CAPT786'));
    });

    test('parses code from Play Store install referrer captain_code=CAPT482', () {
      final code = ReferralLinkService.parseCodeFromString('captain_code=CAPT482');
      expect(code, equals('CAPT482'));
    });

    test('parses code from complex multi-param Play Store install referrer', () {
      final raw = 'utm_source=google&utm_medium=cpc&captain_code=SWIFT0&anid=admob';
      final code = ReferralLinkService.parseCodeFromString(raw);
      expect(code, equals('SWIFT0'));
    });

    test('parses URL-encoded referrer string captain_code%3DCAPT999', () {
      final raw = 'captain_code%3DCAPT999';
      final code = ReferralLinkService.parseCodeFromString(raw);
      expect(code, equals('CAPT999'));
    });

    test('parses nested referrer parameter referrer=captain_code%3DCAPT123', () {
      final raw = 'referrer=captain_code%3DCAPT123';
      final code = ReferralLinkService.parseCodeFromString(raw);
      expect(code, equals('CAPT123'));
    });

    test('saves, retrieves, and clears pending referral code in persistent storage', () async {
      final service = ReferralLinkService();
      await service.clearPendingReferralCode();
      expect(await service.getPendingReferralCode(), isNull);

      await service.savePendingReferralCode('capt482');
      expect(await service.getPendingReferralCode(), equals('CAPT482'));

      await service.clearPendingReferralCode();
      expect(await service.getPendingReferralCode(), isNull);
    });
  });
}
