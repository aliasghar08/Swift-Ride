import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_offer_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/safety_event_model.dart';
import 'package:swiftride/domain/models/safety_event_type.dart';
import 'package:swiftride/domain/models/subscription_model.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/presentation/auth/phone_auth_screen.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/services/auth_service.dart';
import 'package:swiftride/services/firestore/firestore_driver_service.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';
import 'package:swiftride/services/firestore/firestore_safety_service.dart';
import 'package:swiftride/services/firestore/firestore_user_service.dart';

void main() {
  group('AuthService Tests', () {
    final authService = AuthService();

    test('AuthService falls back gracefully when Firebase is not initialized', () async {
      expect(authService.isAuthenticated, isFalse);
      expect(authService.currentFirebaseUser, isNull);

      String? sentVerificationId;
      int? sentResendToken;

      await authService.sendOtp(
        phoneNumber: '+923000000000',
        onCodeSent: (vId, token) {
          sentVerificationId = vId;
          sentResendToken = token;
        },
        onError: (err) => fail('Should not fail: $err'),
      );

      expect(sentVerificationId, isNotNull);
      expect(sentVerificationId, startsWith('mock_verification_id_'));
      expect(sentResendToken, equals(123456));
    });

    test('AuthService syncUserProfile creates and saves AppUser', () async {
      final user = await authService.syncUserProfile(
        uid: 'test_uid_999',
        phone: '+923001234567',
        fullName: 'Babar Azam',
        defaultRole: UserRole.rider,
      );

      expect(user.id, equals('test_uid_999'));
      expect(user.fullName, equals('Babar Azam'));
      expect(user.phone, equals('+923001234567'));
      expect(user.role, equals(UserRole.rider));
      expect(user.rating, equals(5.0));
      expect(user.totalRides, equals(0));
    });
  });

  group('FirestoreUserService Tests', () {
    final userService = FirestoreUserService();

    test('CRUD in-memory fallback operations', () async {
      final user = AppUser(
        id: 'user_tariq_1',
        phone: '+923019876543',
        fullName: 'Tariq Khan',
        role: UserRole.driver,
        rating: 4.88,
        totalRides: 15,
        createdAt: DateTime.now(),
      );

      await userService.saveUser(user);
      final retrieved = await userService.getUser('user_tariq_1');

      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('user_tariq_1'));
      expect(retrieved.fullName, equals('Tariq Khan'));
      expect(retrieved.role, equals(UserRole.driver));

      await userService.updateFcmToken('user_tariq_1', 'fcm_token_xyz_123');
      final updated = await userService.getUser('user_tariq_1');
      expect(updated!.fcmTokens, contains('fcm_token_xyz_123'));
    });
  });

  group('FirestoreRideService Tests', () {
    final rideService = FirestoreRideService();

    test('Complete ride lifecycle: create, offer, arrive, verify PIN, complete', () async {
      final ride = RideModel(
        id: 'ride_test_pk_101',
        riderId: 'rider_ali_77',
        status: RideStatus.requested,
        pickup: const LocationPoint(latitude: 33.6844, longitude: 73.0479, address: 'Blue Area, Islamabad'),
        dropoff: const LocationPoint(latitude: 33.7294, longitude: 73.0931, address: 'F-7 Markaz, Islamabad'),
        offeredFare: 350.0, // PKR 350
        suggestedFare: 320.0,
        distanceKm: 6.5,
        durationMin: 14.0,
        commissionAmount: 0.0,
        pin: '7890',
        createdAt: DateTime.now(),
      );

      // 1. Create ride
      await rideService.createRide(ride);
      var fetched = await rideService.getRide('ride_test_pk_101');
      expect(fetched, isNotNull);
      expect(fetched!.status, equals(RideStatus.requested));
      expect(fetched.offeredFare, equals(350.0));

      // 2. Submit counter-offer (PKR 380)
      final offer = RideOffer(
        id: 'offer_test_1',
        rideId: 'ride_test_pk_101',
        driverId: 'driver_imran_55',
        driverName: 'Imran Abbas',
        counterFare: 380.0,
        etaMinutes: 4,
        vehicleSummary: 'White Suzuki Alto (ISB-9988)',
        driverRating: 4.92,
        createdAt: DateTime.now(),
      );
      await rideService.submitOffer(offer);

      // 3. Accept offer
      await rideService.acceptOffer('ride_test_pk_101', offer);
      fetched = await rideService.getRide('ride_test_pk_101');
      expect(fetched!.status, equals(RideStatus.accepted));
      expect(fetched.driverId, equals('driver_imran_55'));
      expect(fetched.acceptedFare, equals(380.0));

      // 4. Mark driver arrived
      await rideService.markDriverArrived('ride_test_pk_101');
      fetched = await rideService.getRide('ride_test_pk_101');
      expect(fetched!.status, equals(RideStatus.driverArrived));

      // 5. Verify 4-digit PIN (invalid and valid)
      final invalidPinResult = await rideService.verifyPinAndStartTrip('ride_test_pk_101', '0000');
      expect(invalidPinResult, isFalse);

      final validPinResult = await rideService.verifyPinAndStartTrip('ride_test_pk_101', '7890');
      expect(validPinResult, isTrue);

      fetched = await rideService.getRide('ride_test_pk_101');
      expect(fetched!.status, equals(RideStatus.inProgress));

      // 6. Complete trip
      await rideService.completeTrip('ride_test_pk_101');
      fetched = await rideService.getRide('ride_test_pk_101');
      expect(fetched!.status, equals(RideStatus.completed));
      expect(fetched.paymentStatus, equals('paid'));
    });
  });

  group('FirestoreDriverService Tests', () {
    final driverService = FirestoreDriverService();

    test('Driver profile persistence and live telemetry updates', () async {
      final profile = DriverProfile(
        userId: 'driver_hamza_88',
        licenseNumber: 'ISB-DL-48201',
        vehicle: const VehicleInfo(
          make: 'Toyota',
          model: 'Corolla',
          year: 2021,
          plate: 'LEE-4400',
          color: 'Super White',
        ),
        isVerified: true,
        isOnline: true,
        subscriptionStatus: SubscriptionStatus.trial,
        subscriptionExpiresAt: DateTime.now().add(const Duration(days: 365)),
        rating: 4.96,
        totalRides: 88,
        totalEarnings: 45000.0, // PKR 45,000
        latitude: 33.6844,
        longitude: 73.0479,
        createdAt: DateTime.now(),
      );

      await driverService.saveDriverProfile(profile);
      var fetched = await driverService.getDriverProfile('driver_hamza_88');
      expect(fetched, isNotNull);
      expect(fetched!.licenseNumber, equals('ISB-DL-48201'));
      expect(fetched.vehicle.model, equals('Corolla'));

      await driverService.updateOnlineStatus('driver_hamza_88', false);
      fetched = await driverService.getDriverProfile('driver_hamza_88');
      expect(fetched!.isOnline, isFalse);

      await driverService.updateDriverLocation(
        driverId: 'driver_hamza_88',
        latitude: 33.7100,
        longitude: 73.0550,
      );
      fetched = await driverService.getDriverProfile('driver_hamza_88');
      expect(fetched!.latitude, closeTo(33.7100, 0.001));
      expect(fetched.longitude, closeTo(73.0550, 0.001));
    });
  });

  group('FirestoreSafetyService Tests', () {
    final safetyService = FirestoreSafetyService();

    test('Records SOS alert and generates shared trip token', () async {
      final event = SafetyEvent(
        id: 'sos_alert_1',
        rideId: 'ride_test_pk_101',
        type: SafetyEventType.sos,
        latitude: 33.6844,
        longitude: 73.0479,
        metadata: {
          'message': 'Emergency dispatched',
          'alertLevel': 'CRITICAL',
        },
        createdAt: DateTime.now(),
      );

      await safetyService.recordSafetyEvent(event);
      final events = await safetyService.getRideSafetyEvents('ride_test_pk_101');
      expect(events.length, equals(1));
      expect(events.first.type, equals(SafetyEventType.sos));

      // Public trip share token
      await safetyService.saveSharedTripToken(
        token: 'share_token_abc',
        rideId: 'ride_test_pk_101',
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
      );

      final rideId = await safetyService.getRideIdByShareToken('share_token_abc');
      expect(rideId, equals('ride_test_pk_101'));
    });
  });

  group('PhoneAuthScreen Widget Tests', () {
    testWidgets('Renders phone authentication UI and autofills test number', (WidgetTester tester) async {
      final auth = AuthProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: CustomChangeNotifierProvider<AuthProvider>(
            notifier: auth,
            child: const PhoneAuthScreen(),
          ),
        ),
      );

      // Verify UI elements
      expect(find.text('Enter Phone Number'), findsOneWidget);
      expect(find.text('+92'), findsOneWidget);
      expect(find.text('Send OTP Code'), findsOneWidget);
      expect(find.text('Fill Demo / Test Number (+92 300 0000000)'), findsOneWidget);

      // Tap demo button
      await tester.tap(find.text('Fill Demo / Test Number (+92 300 0000000)'));
      await tester.pumpAndSettle();

      expect(find.text('3000000000'), findsOneWidget);

      // Tap Send OTP
      await tester.tap(find.text('Send OTP Code'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Should transition to OTP screen
      expect(find.text('Verify OTP Code'), findsOneWidget);
      expect(find.text('Verify & Continue'), findsOneWidget);
    });
  });
}
