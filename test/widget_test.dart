import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/providers/admin_provider.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/providers/safety_provider.dart';
import 'package:swiftride/ai/ai.dart';
import 'package:swiftride/main.dart';

void main() {
  testWidgets('SwiftRide App loads with Rider Mode and Zero Commission branding', (WidgetTester tester) async {
    // Set a realistic mobile screen size for testing
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final authProvider = AuthProvider();
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
        child: const SwiftRideApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Verify brand title and 0% fee badge
    expect(find.text('SwiftRide'), findsWidgets);
    expect(find.text('0% Fee (Year 1)'), findsOneWidget);

    // Verify Rider view is loaded initially
    expect(find.text('Rider'), findsWidgets);
    expect(find.text('Where to? (Destination)'), findsOneWidget);
    // Fare preview is only visible when destination is selected
    expect(find.text('Your Offer (Rider sets the price):'), findsNothing);
    expect(find.text('Find Nearby Drivers (0% Commission)'), findsNothing);

    // Switch to Driver Mode
    await tester.tap(find.text('Driver'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Driver view
    expect(find.text('Driver Dashboard'), findsOneWidget);
    expect(find.text('Year 1: PKR 0 Fee'), findsOneWidget);

    // Switch to Admin Mode
    await tester.tap(find.text('Admin'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Admin view
    expect(find.text('SwiftRide Operations & Admin Dashboard'), findsOneWidget);
    expect(find.text('Driver Verification Queue'), findsOneWidget);
  });

  testWidgets('Pixel-perfect layout verification across Compact, Mobile, Tablet, and Desktop screens', (WidgetTester tester) async {
    final screenSizes = [
      const Size(320, 568),   // Compact Mobile (e.g. iPhone SE 1st gen)
      const Size(390, 844),   // Standard Mobile (iPhone 13/14/15)
      const Size(768, 1024),  // Tablet (iPad Mini / Portrait)
      const Size(1280, 800),  // Desktop / Landscape Tablet
    ];

    for (final size in screenSizes) {
      tester.view.physicalSize = size * 2.0;
      tester.view.devicePixelRatio = 2.0;

      final authProvider = AuthProvider();
      final driverProvider = DriverProvider();
      final locationProvider = LocationProvider(autoStart: false);
      final rideProvider = RideProvider();
      final safetyProvider = SafetyProvider();
      final adminProvider = AdminProvider();
      final safetyCheckProvider = SafetyCheckProvider();
      final aiChatProvider = AiChatProvider();
      final earningsAdvisorProvider = EarningsAdvisorProvider();

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
          child: const SwiftRideApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // In Rider mode: Verify no rendering overflows occur
      expect(tester.takeException(), isNull);
      expect(find.text('SwiftRide'), findsWidgets);

      // Switch to Driver mode: Verify no rendering overflows occur
      await tester.tap(find.text('Driver'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Driver Dashboard'), findsOneWidget);

      // Switch to Admin mode: Verify no rendering overflows occur
      await tester.tap(find.text('Admin'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('SwiftRide Operations & Admin Dashboard'), findsOneWidget);

      authProvider.dispose();
      driverProvider.dispose();
      locationProvider.dispose();
      rideProvider.dispose();
      safetyProvider.dispose();
      adminProvider.dispose();
    }

    tester.view.resetPhysicalSize();
  });
}
