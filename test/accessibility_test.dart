import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/ai/ai.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/main.dart';
import 'package:swiftride/providers/admin_provider.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/providers/safety_provider.dart';

void main() {
  /// Pumps the real app shell so the app bar chrome is under test.
  Future<void> pumpApp(WidgetTester tester, {RideModel? initialRide}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final authProvider = AuthProvider();
    final driverProvider = DriverProvider();
    final locationProvider = LocationProvider(autoStart: false);
    final rideProvider = RideProvider(initialRide: initialRide);
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
          (child) => CustomChangeNotifierProvider<AiChatProvider>(
                notifier: aiChatProvider,
                child: child,
              ),
          (child) => CustomChangeNotifierProvider<EarningsAdvisorProvider>(
                notifier: earningsAdvisorProvider,
                child: child,
              ),
          (child) => CustomChangeNotifierProvider<SafetyCheckProvider>(
                notifier: safetyCheckProvider,
                child: child,
              ),
        ],
        child: const SwiftRideApp(),
      ),
    );
    // Let entry animations finish: a widget mid-fade (opacity 0) is excluded
    // from the semantics tree, so assertions would see an empty node.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('App bar accessibility', () {
    testWidgets('role switcher exposes a semantics label and selected state', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);

      // The switcher used to be a bare GestureDetector with no label at all.
      expect(find.bySemanticsLabel('Rider mode'), findsOneWidget);
      expect(find.bySemanticsLabel('Driver mode'), findsOneWidget);
      expect(find.bySemanticsLabel('Admin mode'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('trip status is announced as a live region', (tester) async {
      final handle = tester.ensureSemantics();

      final ride = RideModel(
        id: 'ride_a11y',
        riderId: 'rider_1',
        driverId: 'driver_1',
        status: RideStatus.accepted,
        pickup: const LocationPoint(latitude: 33.70, longitude: 73.05, address: 'A'),
        dropoff: const LocationPoint(latitude: 33.56, longitude: 72.85, address: 'B'),
        offeredFare: 500,
        suggestedFare: 520,
        distanceKm: 5.2,
        durationMin: 12,
        pin: '4321',
        createdAt: DateTime.now(),
      );

      await pumpApp(tester, initialRide: ride);

      // The status chip must be a live region so a status change is spoken,
      // rather than the user having to navigate back to it.
      // Matched by pattern: the incoming label merges with the chip's own text.
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Trip status: Driver En Route')),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);

      handle.dispose();
    });

    testWidgets('the map exposes a screen-reader description', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);

      // A map is otherwise opaque to assistive technology — it previously had no
      // semantics node at all, so a screen-reader user got no indication of what
      // was on screen.
      expect(
        find.bySemanticsLabel(RegExp('Map of your area')),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('role switcher meets the 48dp minimum touch target', (tester) async {
      await pumpApp(tester);

      // WCAG 2.5.5 — the visual pill stays compact but the tappable area must
      // not be smaller than 48x48.
      final size = tester.getSize(find.bySemanticsLabel('Rider mode'));
      expect(size.height, greaterThanOrEqualTo(48.0));
      expect(size.width, greaterThanOrEqualTo(48.0));
    });
  });
}
