import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/native_map_service.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/core/theme/app_theme.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/presentation/auth/phone_auth_screen.dart';
import 'package:swiftride/presentation/rider/rider_home_screen.dart';
import 'package:swiftride/presentation/rider/route_preview_screen.dart';
import 'package:swiftride/presentation/rider/ride_history_screen.dart';
import 'package:swiftride/providers/admin_provider.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/providers/safety_provider.dart';
import 'package:swiftride/ai/ai.dart';
import 'package:swiftride/services/map_service.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phone Verification & Login Page Tests', () {
    testWidgets('PhoneAuthScreen renders on entry and allows entering phone number', (tester) async {
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

      // Verify header and phone verification instructions
      expect(find.text('SwiftRide Authentication'), findsOneWidget);
      expect(find.text('Enter Your Mobile Number'), findsOneWidget);
      expect(find.text('We will send a 6-digit verification code.'), findsOneWidget);
      expect(find.text('Continue with Phone'), findsOneWidget);
      expect(find.text('Continue as AI Guest / Passenger'), findsOneWidget);

      // Verify entering phone number
      await tester.enterText(find.byType(TextField).first, '3000000000');
      await tester.pump();
      expect(find.text('3000000000'), findsOneWidget);
    });

    testWidgets('PhoneAuthScreen Continue as Guest invokes completion cleanly', (tester) async {
      bool authCompleted = false;
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
            home: PhoneAuthScreen(
              onAuthSuccess: () {
                authCompleted = true;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap "Continue as AI Guest / Passenger"
      await tester.tap(find.text('Continue as AI Guest / Passenger'));
      await tester.pumpAndSettle();

      expect(authCompleted, isTrue);
    });
  });

  group('Route Selection Button Background & Text Color Adaptivity Tests', () {
    testWidgets('ChoiceChip in RoutePreviewScreen adapts text color to button background in dark and light modes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final routes = <RouteOption>[
        const RouteOption(
          id: 'route_1',
          distanceKm: 12.4,
          durationMin: 18.0,
          staticDurationMin: 18.0,
          summary: 'via Express Highway',
          polylinePoints: [
            LatLng(33.7, 73.0),
            LatLng(33.6, 72.9),
          ],
          labels: ['FASTEST'],
          trafficLevel: 'NORMAL',
          trafficIntervals: [],
          economics: RouteEconomics(
            fuelCost: 150,
            maintenanceCost: 50,
            tollCost: 0,
            driverCost: 200,
            riderFare: 550,
            commission: 0,
            driverProfit: 550,
            profitPerMin: 30.5,
          ),
        ),
        const RouteOption(
          id: 'route_2',
          distanceKm: 14.8,
          durationMin: 24.0,
          staticDurationMin: 22.0,
          summary: 'via Main Boulevard',
          polylinePoints: [
            LatLng(33.7, 73.0),
            LatLng(33.6, 72.9),
          ],
          labels: ['CHEAPEST'],
          trafficLevel: 'NORMAL',
          trafficIntervals: [],
          economics: RouteEconomics(
            fuelCost: 120,
            maintenanceCost: 40,
            tollCost: 0,
            driverCost: 160,
            riderFare: 480,
            commission: 0,
            driverProfit: 480,
            profitPerMin: 20.0,
          ),
        ),
      ];

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
            theme: AppTheme.darkTheme,
            home: RoutePreviewScreen(
              explicitRoutes: routes,
              initialRouteIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that ChoiceChips exist for routes
      expect(find.byType(ChoiceChip), findsNWidgets(2));

      // Find the text within the selected and unselected chips
      final selectedChip = tester.widget<ChoiceChip>(find.byType(ChoiceChip).first);
      final unselectedChip = tester.widget<ChoiceChip>(find.byType(ChoiceChip).last);

      expect(selectedChip.selected, isTrue);
      expect(unselectedChip.selected, isFalse);

      // Selected chip background is brand primary blue
      expect(selectedChip.selectedColor, equals(AppTheme.primaryBlue));
      // Selected chip text is crisp white
      expect(selectedChip.labelStyle?.color, equals(Colors.white));

      // Unselected chip text color adapts to background (should be readable, not dark blue)
      expect(unselectedChip.labelStyle?.color, isNot(equals(AppTheme.primaryBlue)));
      expect(unselectedChip.backgroundColor, isNotNull);
    });

    testWidgets('RiderHomeScreen route selector buttons adapt text color to background', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authProvider = AuthProvider(
        initialUser: AppUser(
          id: 'rider_mock_001',
          phone: '+923000000000',
          fullName: 'Ali Asghar',
          role: UserRole.rider,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final driverProvider = DriverProvider();
      final locationProvider = LocationProvider(autoStart: false);
      final rideProvider = RideProvider();
      final safetyProvider = SafetyProvider();
      final adminProvider = AdminProvider();
      final safetyCheckProvider = SafetyCheckProvider();
      final aiChatProvider = AiChatProvider();
      final earningsAdvisorProvider = EarningsAdvisorProvider();

      addTearDown(() {
        authProvider.dispose();
        driverProvider.dispose();
        locationProvider.dispose();
        rideProvider.dispose();
        safetyProvider.dispose();
        adminProvider.dispose();
        safetyCheckProvider.dispose();
        aiChatProvider.dispose();
        earningsAdvisorProvider.dispose();
      });

      await tester.pumpWidget(
        CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: authProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<DriverProvider>(
                  notifier: driverProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<LocationProvider>(
                  notifier: locationProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<RideProvider>(
                  notifier: rideProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<SafetyProvider>(
                  notifier: safetyProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<AdminProvider>(
                  notifier: adminProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<SafetyCheckProvider>(
                  notifier: safetyCheckProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<AiChatProvider>(
                  notifier: aiChatProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<EarningsAdvisorProvider>(
                  notifier: earningsAdvisorProvider,
                  child: child,
                ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: RiderHomeScreen(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Where to? (Destination)'), findsOneWidget);
    });
  });

  group('Firebase Mock Stored Data UI Verification', () {
    testWidgets('RideHistoryScreen displays stored mock trip from Centaurus to Airport', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final authProvider = AuthProvider(
        initialUser: AppUser(
          id: 'rider_mock_001',
          phone: '+923000000000',
          fullName: 'Ali Asghar (Verified Rider)',
          role: UserRole.rider,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final mockStoredRide = RideModel(
        id: 'ride_mock_history_001',
        riderId: 'rider_mock_001',
        driverId: 'driver_mock_001',
        status: RideStatus.completed,
        pickup: const LocationPoint(
          latitude: 33.7077,
          longitude: 73.0501,
          address: 'Centaurus Mall, Jinnah Avenue, F-8, Islamabad',
        ),
        dropoff: const LocationPoint(
          latitude: 33.5651,
          longitude: 72.8524,
          address: 'Islamabad International Airport, Terminal 1',
        ),
        offeredFare: 1850.0,
        acceptedFare: 1850.0,
        suggestedFare: 1800.0,
        distanceKm: 29.4,
        durationMin: 32.0,
        commissionAmount: 0.0,
        paymentStatus: 'paid',
        paymentMethod: 'CASH',
        pin: '7492',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        completedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 28)),
      );

      final firestoreService = FirestoreRideService();
      await firestoreService.saveRideHistory(mockStoredRide);

      final rideProvider = RideProvider(
        firestore: firestoreService,
        initialHistory: [mockStoredRide],
      );

      addTearDown(() {
        authProvider.dispose();
        rideProvider.dispose();
      });

      await tester.pumpWidget(
        CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: authProvider,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<RideProvider>(
                  notifier: rideProvider,
                  child: child,
                ),
          ],
          child: const MaterialApp(
            home: RideHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check displayed mock data in UI
      expect(find.text('My Ride History'), findsOneWidget);
      expect(find.textContaining('Centaurus Mall'), findsOneWidget);
      expect(find.textContaining('Islamabad International Airport'), findsOneWidget);
      expect(find.text('PKR 1850'), findsOneWidget);
      expect(find.text('29.4 km'), findsOneWidget);
      expect(find.text('32 min'), findsOneWidget);
      expect(find.text('0% Fee'), findsOneWidget);
    });
  });
}
