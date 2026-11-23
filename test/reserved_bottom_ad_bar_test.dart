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
import 'package:swiftride/presentation/common/reserved_bottom_ad_bar.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestHost({
    required AuthProvider auth,
    DriverProvider? driver,
    RideProvider? ride,
  }) {
    return MaterialApp(
      home: CustomMultiProvider(
        providers: [
          (child) => CustomChangeNotifierProvider<AuthProvider>(
                notifier: auth,
                child: child,
              ),
          if (driver != null)
            (child) => CustomChangeNotifierProvider<DriverProvider>(
                  notifier: driver,
                  child: child,
                ),
          if (ride != null)
            (child) => CustomChangeNotifierProvider<RideProvider>(
                  notifier: ride,
                  child: child,
                ),
        ],
        child: const Scaffold(
          body: Center(child: Text('Main Content')),
          bottomNavigationBar: ReservedBottomAdBar(),
        ),
      ),
    );
  }

  group('ReservedBottomAdBar Tests', () {
    testWidgets('Shows for unauthenticated users (login / phone auth screen)', (tester) async {
      final auth = AuthProvider();
      await tester.pumpWidget(buildTestHost(auth: auth));
      await tester.pump();

      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);
    });

    testWidgets('Hides for Admin role', (tester) async {
      final user = AppUser(
        id: 'admin_1',
        phone: '+923001234567',
        fullName: 'Admin User',
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.admin);

      await tester.pumpWidget(buildTestHost(auth: auth));
      await tester.pump();

      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsNothing);
    });

    testWidgets('Shows 60 dp reserved bar for Rider role', (tester) async {
      final user = AppUser(
        id: 'rider_1',
        phone: '+923001234567',
        fullName: 'Rider User',
        role: UserRole.rider,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.rider);

      await tester.pumpWidget(buildTestHost(auth: auth));
      await tester.pump();

      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);
      final size = tester.getSize(find.byKey(const Key('reserved_bottom_ad_bar')));
      expect(size.height, 60.0);
    });

    testWidgets('Shows for Rider role even during active ride / driving', (tester) async {
      final user = AppUser(
        id: 'rider_1',
        phone: '+923001234567',
        fullName: 'Rider User',
        role: UserRole.rider,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.rider);

      final activeRide = RideModel(
        id: 'ride_1',
        riderId: 'rider_1',
        driverId: 'driver_1',
        pickup: const LocationPoint(latitude: 31.0, longitude: 72.0, address: 'Pickup'),
        dropoff: const LocationPoint(latitude: 31.1, longitude: 72.1, address: 'Dropoff'),
        offeredFare: 200,
        suggestedFare: 200,
        distanceKm: 5.0,
        durationMin: 15,
        pin: '1234',
        status: RideStatus.inProgress,
        createdAt: DateTime.now(),
      );
      final ride = RideProvider(initialRide: activeRide);

      await tester.pumpWidget(buildTestHost(auth: auth, ride: ride));
      await tester.pump();

      // Passengers always see ads even while driving
      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);
    });

    testWidgets('Shows for Driver when Offline and no active ride', (tester) async {
      final user = AppUser(
        id: 'driver_1',
        phone: '+923001234567',
        fullName: 'Driver User',
        role: UserRole.driver,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.driver);

      final driver = DriverProvider();
      driver.updateProfile(
        DriverProfile(
          userId: 'driver_1',
          licenseNumber: 'DL-12345',
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'LEA-1234',
            color: 'White',
            type: 'car',
          ),
          isOnline: false,
          subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
        ),
      );

      final ride = RideProvider();

      await tester.pumpWidget(buildTestHost(auth: auth, driver: driver, ride: ride));
      await tester.pump();

      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);
    });

    testWidgets('Shows for Driver when Online and idle (no active ride)', (tester) async {
      final user = AppUser(
        id: 'driver_1',
        phone: '+923001234567',
        fullName: 'Driver User',
        role: UserRole.driver,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.driver);

      final driver = DriverProvider();
      driver.updateProfile(
        DriverProfile(
          userId: 'driver_1',
          licenseNumber: 'DL-12345',
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'LEA-1234',
            color: 'White',
            type: 'car',
          ),
          isOnline: true,
          subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
        ),
      );

      final ride = RideProvider();

      await tester.pumpWidget(buildTestHost(auth: auth, driver: driver, ride: ride));
      await tester.pump();

      // Driver waiting for rides sees ads on screens
      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsOneWidget);
    });

    testWidgets('Hides for Driver during active ride (driving)', (tester) async {
      final user = AppUser(
        id: 'driver_1',
        phone: '+923001234567',
        fullName: 'Driver User',
        role: UserRole.driver,
        createdAt: DateTime.now(),
      );
      final auth = AuthProvider(initialUser: user, initialRole: UserRole.driver);

      final driver = DriverProvider();
      driver.updateProfile(
        DriverProfile(
          userId: 'driver_1',
          licenseNumber: 'DL-12345',
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'LEA-1234',
            color: 'White',
            type: 'car',
          ),
          isOnline: true,
          subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
        ),
      );

      final activeRide = RideModel(
        id: 'ride_1',
        riderId: 'rider_1',
        driverId: 'driver_1',
        pickup: const LocationPoint(latitude: 31.0, longitude: 72.0, address: 'Pickup'),
        dropoff: const LocationPoint(latitude: 31.1, longitude: 72.1, address: 'Dropoff'),
        offeredFare: 200,
        suggestedFare: 200,
        distanceKm: 5.0,
        durationMin: 15,
        pin: '1234',
        status: RideStatus.inProgress,
        createdAt: DateTime.now(),
      );

      final ride = RideProvider(initialRide: activeRide);

      await tester.pumpWidget(buildTestHost(auth: auth, driver: driver, ride: ride));
      await tester.pump();

      expect(find.byKey(const Key('reserved_bottom_ad_bar')), findsNothing);
    });
  });
}
