import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/services/native/native_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Women-Only Mode Domain Models', () {
    test('AppUser handles gender and isGenderVerified', () {
      final user = AppUser(
        id: 'u123',
        fullName: 'Fatima',
        role: UserRole.rider,
        createdAt: DateTime.now(),
        gender: 'female',
        isGenderVerified: true,
      );

      final map = user.toMap();
      expect(map['gender'], 'female');
      expect(map['isGenderVerified'], true);

      final reconstructed = AppUser.fromMap(map);
      expect(reconstructed.gender, 'female');
      expect(reconstructed.isGenderVerified, true);

      final updated = user.copyWith(isGenderVerified: false);
      expect(updated.isGenderVerified, false);
      expect(updated.gender, 'female');
    });

    test('DriverProfile handles femalePassengersOnly, gender, and isGenderVerified', () {
      final profile = DriverProfile.empty(userId: 'd123').copyWith(
        gender: 'female',
        isGenderVerified: true,
        femalePassengersOnly: true,
      );

      final map = profile.toMap();
      expect(map['gender'], 'female');
      expect(map['isGenderVerified'], true);
      expect(map['femalePassengersOnly'], true);

      final parsed = DriverProfile.fromMap(map);
      expect(parsed.gender, 'female');
      expect(parsed.isGenderVerified, true);
      expect(parsed.femalePassengersOnly, true);

      final toggled = profile.copyWith(femalePassengersOnly: false);
      expect(toggled.femalePassengersOnly, false);
      expect(toggled.gender, 'female');
    });

    test('RideModel serializes femaleDriverOnly and riderGender', () {
      final ride = RideModel(
        id: 'r123',
        riderId: 'u123',
        pickup: const LocationPoint(latitude: 33.6844, longitude: 73.0479, address: 'Islamabad'),
        dropoff: const LocationPoint(latitude: 33.6944, longitude: 73.0579, address: 'Rawalpindi'),
        offeredFare: 450.0,
        suggestedFare: 450.0,
        distanceKm: 12.5,
        durationMin: 20,
        pin: '1234',
        createdAt: DateTime.now(),
        status: RideStatus.requested,
        femaleDriverOnly: true,
        riderGender: 'female',
      );

      final map = ride.toMap();
      expect(map['femaleDriverOnly'], true);
      expect(map['riderGender'], 'female');

      final reconstructed = RideModel.fromMap(map);
      expect(reconstructed.femaleDriverOnly, true);
      expect(reconstructed.riderGender, 'female');

      final altered = ride.copyWith(femaleDriverOnly: false);
      expect(altered.femaleDriverOnly, false);
      expect(altered.riderGender, 'female');
    });
  });

  group('DriverProvider Women-Only Gating Logic', () {
    test('Unverified driver cannot enable femalePassengersOnly', () async {
      final provider = DriverProvider();
      provider.setDriverProfileForTesting(DriverProfile.empty(userId: 'd_unverified').copyWith(
        gender: 'female',
        isVerified: false,
        isGenderVerified: false,
      ));

      final err = await provider.toggleFemalePassengersOnly(true);
      expect(err, isNotNull);
      expect(err, contains('verification'));
      expect(provider.femalePassengersOnly, false);
    });

    test('Male driver cannot enable femalePassengersOnly', () async {
      final provider = DriverProvider();
      provider.setDriverProfileForTesting(DriverProfile.empty(userId: 'd_male').copyWith(
        gender: 'male',
        isVerified: true,
        isGenderVerified: true,
      ));

      final err = await provider.toggleFemalePassengersOnly(true);
      expect(err, isNotNull);
      expect(err, contains('female drivers'));
      expect(provider.femalePassengersOnly, false);
    });

    test('Verified female driver can enable and disable femalePassengersOnly', () async {
      final provider = DriverProvider();
      provider.setDriverProfileForTesting(DriverProfile.empty(userId: 'd_female').copyWith(
        gender: 'female',
        isVerified: true,
        isGenderVerified: true,
        femalePassengersOnly: false,
      ));

      // Turning on
      final errOn = await provider.toggleFemalePassengersOnly(true);
      expect(errOn, isNull);
      expect(provider.femalePassengersOnly, true);

      // Turning off
      final errOff = await provider.toggleFemalePassengersOnly(false);
      expect(errOff, isNull);
      expect(provider.femalePassengersOnly, false);
    });
  });

  group('Promotional Banner Native Storage State Persistence', () {
    test('Driver and Rider promo dismiss keys save and retrieve via NativeStorageService', () async {
      const driverPromoKey = 'promo_dismissed_women_driver_mode_v1';
      const riderPromoKey = 'promo_dismissed_women_rider_mode_v1';
      final storage = NativeStorageService();

      await storage.setBool(driverPromoKey, true);
      final driverDismissed = await storage.getBool(driverPromoKey);
      expect(driverDismissed, true);

      await storage.setBool(riderPromoKey, true);
      final riderDismissed = await storage.getBool(riderPromoKey);
      expect(riderDismissed, true);
    });
  });
}
