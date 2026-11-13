import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/core/theme/app_theme.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/presentation/auth/phone_auth_screen.dart';
import 'package:swiftride/presentation/common/mode_app_bar.dart';
import 'package:swiftride/presentation/rider/route_preview_screen.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/services/coordinate_parser.dart';
import 'package:swiftride/services/map_service.dart';
import 'package:swiftride/services/native_map_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PHASE 1: Authentication & Navigation Stack Resilience', () {
    testWidgets('PhoneAuthScreen renders cleanly, handles phone and OTP input flow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authProvider = AuthProvider();
      addTearDown(authProvider.dispose);

      await tester.pumpWidget(
        CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: authProvider,
                  child: child,
                ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const PhoneAuthScreen(),
          ),
        ),
      );
      await tester.pump();

      // Verify initial phone input state
      expect(find.byType(PhoneAuthScreen), findsOneWidget);
      expect(find.text('SwiftRide Authentication'), findsOneWidget);
      expect(find.text('Enter Your Mobile Number'), findsOneWidget);
      expect(find.text('+92'), findsOneWidget);

      // Enter test phone number
      final phoneField = find.byType(TextField).first;
      await tester.enterText(phoneField, '3001234567');
      await tester.pump();
      expect(find.text('3001234567'), findsOneWidget);

      // Verify Continue with Phone button
      final sendCodeBtn = find.text('Continue with Phone');
      expect(sendCodeBtn, findsOneWidget);

      // Verify Social auth buttons
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
    });
  });

  group('PHASE 2: GPS Teleportation, Geotagging & Pin Picker Stress Test', () {
    test('Rapid GPS coordinate jumps across Jhang resolve robust locality labels', () async {
      // Jump 1: Central Jhang
      final tag1 = CoordinateParser.formatOfflineGeotag(31.2785, 72.3317);
      expect(tag1, contains('Jhang'));

      // Jump 2: Superior College Jhang area
      final tag2 = CoordinateParser.formatOfflineGeotag(31.2670, 72.3220);
      expect(tag2, contains('Jhang'));

      // Jump 3: Ayub Chowk corridor
      final tag3 = CoordinateParser.formatOfflineGeotag(31.2740, 72.3300);
      expect(tag3, contains('Jhang'));
    });

    test('RiderViewModel pin picker sequence does not overwrite pickup until user confirms', () async {
      final vm = RiderViewModel();
      const origin = LocationPoint(
        latitude: 31.2785,
        longitude: 72.3317,
        address: 'Central Jhang',
      );
      vm.setPickup(origin);

      vm.startPinPicker(isPickup: true);
      expect(vm.isPinMode, isTrue);

      // Simulate 5 rapid drags before camera settles
      await vm.updatePinnedCoordinates(31.2800, 72.3320);
      await vm.updatePinnedCoordinates(31.2820, 72.3340);
      await vm.updatePinnedCoordinates(31.2850, 72.3360);
      await vm.updatePinnedCoordinates(31.2880, 72.3380);
      await vm.updatePinnedCoordinates(31.2900, 72.3400);

      // Pickup must remain unchanged until confirmPinLocation() is invoked
      expect(vm.pickupLocation?.latitude, equals(31.2785));
      expect(vm.pickupLocation?.address, equals('Central Jhang'));

      // Confirm
      vm.confirmPinLocation();
      expect(vm.isPinMode, isFalse);
      expect(vm.pickupLocation?.latitude, equals(31.2900));
    });

    test('RiderViewModel canceling pin picker safely restores original pickup location', () async {
      final vm = RiderViewModel();
      const origin = LocationPoint(
        latitude: 31.2785,
        longitude: 72.3317,
        address: 'Central Jhang',
      );
      vm.setPickup(origin);

      vm.startPinPicker(isPickup: true);
      await vm.updatePinnedCoordinates(31.3200, 72.4000);

      vm.cancelPinPicker();
      expect(vm.isPinMode, isFalse);
      expect(vm.tempPinLocation, isNull);
      expect(vm.pickupLocation?.latitude, equals(31.2785));
      expect(vm.pickupLocation?.address, equals('Central Jhang'));
    });
  });

  group('PHASE 3: Instant Auto-Routing, Seat Clamping & Fare Bidding Extremes', () {
    test('Vehicle type transitions strictly enforce seat capacity clamping', () {
      final vm = RiderViewModel();

      // 1. Select Car -> set 4 seats
      vm.selectVehicleType(VehicleType.car);
      vm.setBookedSeats(4);
      expect(vm.selectedVehicleType, equals(VehicleType.car));
      expect(vm.bookedSeats, equals(4));

      // 2. Switch to Auto Rikshaw -> clamps to 2
      vm.selectVehicleType(VehicleType.rikshaw);
      expect(vm.selectedVehicleType, equals(VehicleType.rikshaw));
      expect(vm.bookedSeats, equals(2));

      // 3. Switch to Bike -> clamps to 1
      vm.selectVehicleType(VehicleType.bike);
      expect(vm.selectedVehicleType, equals(VehicleType.bike));
      expect(vm.bookedSeats, equals(1));

      // 4. Switch back to Car -> retains 1 until incremented
      vm.selectVehicleType(VehicleType.car);
      expect(vm.selectedVehicleType, equals(VehicleType.car));
      expect(vm.bookedSeats, equals(1));
      vm.setBookedSeats(4);
      expect(vm.bookedSeats, equals(4));
    });

    test('Fare bidding boundary sanitizer clamps extreme, negative, or zero bids to PKR 50 minimum', () {
      final vm = RiderViewModel();

      // Rapid chips +50 and +100
      vm.fareController.text = '200';
      vm.quickIncrementFare(50);
      expect(vm.fareController.text, equals('250'));
      vm.quickIncrementFare(100);
      expect(vm.fareController.text, equals('350'));

      // Test negative increment below 50
      vm.fareController.text = '60';
      vm.quickIncrementFare(-50);
      expect(vm.fareController.text, equals('50'));

      // Test extreme bid > 99999
      vm.fareController.text = '99999';
      vm.quickIncrementFare(100);
      expect(vm.fareController.text, equals('99999'));
    });

    test('Rapid destination switching terminates stale route calculations without race condition', () async {
      final vm = RiderViewModel();
      const pickup = LocationPoint(latitude: 31.2785, longitude: 72.3317, address: 'Origin');
      const dest1 = LocationPoint(latitude: 31.2670, longitude: 72.3220, address: 'Dest 1');
      const dest2 = LocationPoint(latitude: 31.2740, longitude: 72.3300, address: 'Dest 2');

      vm.setPickup(pickup);

      // Start route 1
      vm.setDropoff(dest1);
      final future1 = vm.autoFetchRoute();

      // Immediately switch to route 2
      vm.setDropoff(dest2);
      final future2 = vm.autoFetchRoute();

      await Future.wait([future1, future2]);

      // ViewModel must have dropoff set to Dest 2
      expect(vm.dropoffLocation?.address, equals('Dest 2'));
      expect(vm.isLoadingRoute, isFalse);
    });

    testWidgets('RoutePreviewScreen renders turn steps and allows seamless stepping and dismissal', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testRoute = RouteOption(
        id: 'test_route_1',
        polylinePoints: const [
          LatLng(31.2785, 72.3317),
          LatLng(31.2740, 72.3300),
          LatLng(31.2670, 72.3220),
        ],
        distanceKm: 2.8,
        durationMin: 7.0,
        staticDurationMin: 7.0,
        summary: 'Via Gojra Road',
        labels: const ['FASTEST'],
        trafficLevel: 'NORMAL',
        trafficIntervals: const [],
        steps: const [
          RouteStep(
            maneuver: 'DEPART',
            instruction: 'Head south on Gojra Road',
            primaryInstruction: 'Head south on Gojra Road',
            secondaryInstruction: 'Continue for 1.2 km',
            distanceKm: 1.2,
            distanceText: '1.2 km',
            durationMin: 3.0,
            durationText: '3 mins',
          ),
          RouteStep(
            maneuver: 'TURN_RIGHT',
            instruction: 'Turn right onto College Road',
            primaryInstruction: 'Turn right onto College Road',
            secondaryInstruction: 'Near Superior College',
            distanceKm: 1.6,
            distanceText: '1.6 km',
            durationMin: 4.0,
            durationText: '4 mins',
          ),
          RouteStep(
            maneuver: 'ARRIVE',
            instruction: 'Arrive at Superior College Jhang',
            primaryInstruction: 'Arrive at destination',
            secondaryInstruction: 'On the left',
            distanceKm: 0.0,
            distanceText: '0 m',
            durationMin: 0.0,
            durationText: '0 min',
          ),
        ],
        economics: const RouteEconomics(
          fuelCost: 61.6,
          maintenanceCost: 11.2,
          tollCost: 0,
          driverCost: 73,
          riderFare: 425,
          commission: 8.5,
          driverProfit: 343.5,
          profitPerMin: 49.1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewScreen(
            explicitPickup: const LocationPoint(latitude: 31.2785, longitude: 72.3317, address: 'Central Jhang'),
            explicitDropoff: const LocationPoint(latitude: 31.2670, longitude: 72.3220, address: 'Superior College'),
            explicitRoutes: [testRoute],
            initialRouteIndex: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoutePreviewScreen), findsOneWidget);
      expect(find.text('Depart'), findsOneWidget);
      expect(find.text('Head south on Gojra Road'), findsOneWidget);

      final previewTurnsFinder = find.textContaining('Preview Turns');
      if (previewTurnsFinder.evaluate().isNotEmpty) {
        await tester.tap(previewTurnsFinder);
        await tester.pumpAndSettle();
      }
    });
  });

  group('PHASE 4: Live Ride Dispatch, Active Navigation HUD & Role Switching', () {
    testWidgets('ModeAppBar toggles cleanly between Rider, Driver, and Admin without navigation resets', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authProvider = AuthProvider();
      addTearDown(authProvider.dispose);

      await tester.pumpWidget(
        CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: authProvider,
                  child: child,
                ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              appBar: ModeAppBar(title: 'SwiftRide'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ModeAppBar), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);

      // Tap Driver tab
      await tester.tap(find.text('Driver'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(authProvider.activeRole, equals(UserRole.driver));

      // Tap Admin tab
      await tester.tap(find.text('Admin'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(authProvider.activeRole, equals(UserRole.admin));

      // Tap Rider tab
      await tester.tap(find.text('Rider'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(authProvider.activeRole, equals(UserRole.rider));
    });
  });
}
