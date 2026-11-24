import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/presentation/common/ad_banner_widget.dart';
import 'package:swiftride/presentation/common/reserved_bottom_ad_bar.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/services/ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdVisibilityPolicy Unit Tests', () {
    test('Returns true for Riders across all lifecycle states (idle, searching, bidding, active trip, history, profile)', () {
      // 1. Rider Idle (no active ride)
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: null,
          isNavigationActive: false,
        ),
        isTrue,
      );

      // 2. Rider Searching / Requested
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: RideStatus.requested,
          isNavigationActive: false,
        ),
        isTrue,
      );

      // 4. Rider with Accepted Driver
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: RideStatus.accepted,
          isNavigationActive: false,
        ),
        isTrue,
      );

      // 5. Rider with Arrived Driver
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: RideStatus.driverArrived,
          isNavigationActive: false,
        ),
        isTrue,
      );

      // 6. Rider Actively in IN_PROGRESS Ride
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: RideStatus.inProgress,
          isNavigationActive: true, // Rider viewing navigation route
        ),
        isTrue,
      );

      // 7. Rider Completed Trip
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: RideStatus.completed,
          isNavigationActive: false,
        ),
        isTrue,
      );

      // 8. Rider Cancelled Trip
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: RideStatus.cancelled,
          isNavigationActive: false,
        ),
        isTrue,
      );
    });

    test('Returns true for Drivers when idle/online without an active trip, and on Khata/Earnings/Profile screens', () {
      // 1. Driver Offline and Idle
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: null,
          isNavigationActive: false,
        ),
        isTrue,
      );

      // 2. Driver Online waiting for ride requests
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: null,
          isNavigationActive: false,
          isDriverMode: true,
        ),
        isTrue,
      );

      // 3. Driver reviewing completed trip or Khata sheet
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: RideStatus.completed,
          isNavigationActive: false,
          isDriverMode: true,
        ),
        isTrue,
      );
    });

    test('Returns false EXCLUSIVELY when isDriverMode == true and trip status is ACCEPTED, ARRIVED, or IN_PROGRESS (or active navigation)', () {
      // 1. Driver with Accepted Ride
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: RideStatus.accepted,
          isNavigationActive: false,
          isDriverMode: true,
        ),
        isFalse,
      );

      // 2. Driver with Arrived Status
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: RideStatus.driverArrived,
          isNavigationActive: false,
          isDriverMode: true,
        ),
        isFalse,
      );

      // 3. Driver Actively In-Progress Driving
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: RideStatus.inProgress,
          isNavigationActive: false,
          isDriverMode: true,
        ),
        isFalse,
      );

      // 4. Driver with Active Turn-by-Turn Navigation Running
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: null,
          isNavigationActive: true,
          isDriverMode: true,
        ),
        isFalse,
      );
    });

    test('Safety Critical: Returns false for ALL users during active SOS emergency', () {
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.rider,
          tripStatus: null,
          isSosActive: true,
        ),
        isFalse,
      );

      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.driver,
          tripStatus: null,
          isSosActive: true,
        ),
        isFalse,
      );
    });

    test('Admin Role: Returns false', () {
      expect(
        AdVisibilityPolicy.shouldShowAds(
          role: UserRole.admin,
          tripStatus: null,
        ),
        isFalse,
      );
    });
  });

  group('Ad Lifecycle & Soft Keyboard Persistence Tests', () {
    Widget buildKeyboardTestHarness({
      required AuthProvider auth,
      required EdgeInsets viewInsets,
      RideProvider? ride,
      DriverProvider? driver,
    }) {
      return MaterialApp(
        home: CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: auth,
                  child: child,
                ),
            if (ride != null)
              (child) => CustomChangeNotifierProvider<RideProvider>(
                    notifier: ride,
                    child: child,
                  ),
            if (driver != null)
              (child) => CustomChangeNotifierProvider<DriverProvider>(
                    notifier: driver,
                    child: child,
                  ),
          ],
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 800),
              viewInsets: viewInsets,
            ),
            child: const Scaffold(
              body: Center(child: TextField()),
              bottomNavigationBar: ReservedBottomAdBar(),
            ),
          ),
        ),
      );
    }

    testWidgets('Keyboard appearance (viewInsets.bottom > 0) does NOT dispose or destroy the ad bar widget', (tester) async {
      final user = AppUser(
        id: 'rider_persistence_test',
        phone: '+923001234567',
        fullName: 'Test Rider',
        role: UserRole.rider,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.rider);

      // 1. Initial render with keyboard closed
      await tester.pumpWidget(
        buildKeyboardTestHarness(
          auth: auth,
          viewInsets: EdgeInsets.zero,
        ),
      );
      await tester.pump();

      // Bar is visible with key
      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);
      expect(find.byType(AdBannerWidget), findsOneWidget);

      // Capture state
      final bannerStateBefore = tester.state(find.byType(AdBannerWidget));

      // 2. Soft keyboard opens (viewInsets.bottom = 320)
      await tester.pumpWidget(
        buildKeyboardTestHarness(
          auth: auth,
          viewInsets: const EdgeInsets.only(bottom: 320),
        ),
      );
      await tester.pump();

      // The visible container key is null while keyboard is up to prevent covering inputs
      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsNothing);

      // Crucial: AdBannerWidget is STILL mounted in element tree (under Offstage) and NOT disposed
      expect(find.byType(AdBannerWidget, skipOffstage: false), findsOneWidget);
      final bannerStateDuring = tester.state(find.byType(AdBannerWidget, skipOffstage: false));
      expect(identical(bannerStateBefore, bannerStateDuring), isTrue);

      // 3. Soft keyboard dismisses (viewInsets.bottom = 0)
      await tester.pumpWidget(
        buildKeyboardTestHarness(
          auth: auth,
          viewInsets: EdgeInsets.zero,
        ),
      );
      await tester.pump();

      // Bar immediately restored without re-creation or disposal
      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);
      final bannerStateAfter = tester.state(find.byType(AdBannerWidget));
      expect(identical(bannerStateBefore, bannerStateAfter), isTrue);
    });

    testWidgets('Driver Home Screen displays ads while idle, hides when ride is accepted/inProgress', (tester) async {
      final user = AppUser(
        id: 'driver_test_1',
        phone: '+923001234567',
        fullName: 'Test Driver',
        role: UserRole.driver,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.driver);
      final driver = DriverProvider();
      driver.updateProfile(
        DriverProfile(
          userId: 'driver_test_1',
          licenseNumber: 'DL-9999',
          vehicle: const VehicleInfo(
            make: 'Honda',
            model: 'Civic',
            year: 2023,
            plate: 'ISB-555',
            color: 'Black',
            type: 'car',
          ),
          isOnline: true,
          subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
        ),
      );
      final ride = RideProvider();

      // 1. Driver is online and waiting (idle) -> Ads are visible
      await tester.pumpWidget(
        buildKeyboardTestHarness(
          auth: auth,
          driver: driver,
          ride: ride,
          viewInsets: EdgeInsets.zero,
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);

      // 2. Driver accepts a trip -> Ads are immediately hidden
      final trip = RideModel(
        id: 'ride_active_123',
        riderId: 'rider_abc',
        driverId: 'driver_test_1',
        pickup: const LocationPoint(latitude: 31.0, longitude: 72.0, address: 'Pickup'),
        dropoff: const LocationPoint(latitude: 31.1, longitude: 72.1, address: 'Dropoff'),
        offeredFare: 300,
        suggestedFare: 300,
        distanceKm: 4.0,
        durationMin: 10,
        pin: '5678',
        status: RideStatus.accepted,
        createdAt: DateTime.now(),
      );
      final activeRideProvider = RideProvider(initialRide: trip);

      await tester.pumpWidget(
        buildKeyboardTestHarness(
          auth: auth,
          driver: driver,
          ride: activeRideProvider,
          viewInsets: EdgeInsets.zero,
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsNothing);
    });
  });
}
