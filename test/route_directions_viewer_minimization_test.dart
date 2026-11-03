import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/presentation/common/google_map_view.dart';
import 'package:swiftride/presentation/rider/route_preview_screen.dart';
import 'package:swiftride/services/firestore/firestore_safety_service.dart';
import 'package:swiftride/services/map_service.dart';

void main() {
  group('Directions Viewer Minimization & Turn Visualization Tests', () {
    const pickup = LocationPoint(
      latitude: 33.6844,
      longitude: 73.0479,
      address: 'F-7 Markaz, Islamabad',
    );
    const dropoff = LocationPoint(
      latitude: 33.7294,
      longitude: 73.0931,
      address: 'Lake View Park, Islamabad',
    );

    final sampleSteps = [
      const RouteStep(
        maneuver: 'DEPART',
        instruction: 'Head northeast on Jinnah Ave toward Blue Area',
        primaryInstruction: 'Head northeast on Jinnah Ave',
        secondaryInstruction: 'toward Blue Area',
        distanceKm: 2.1,
        distanceText: '2.1 km',
        durationMin: 4.0,
        durationText: '4 mins',
        roadName: 'Jinnah Ave',
      ),
      const RouteStep(
        maneuver: 'TURN_RIGHT',
        instruction: 'Turn right onto Murree Rd\nPass by Rawal Lake entrance on left',
        primaryInstruction: 'Turn right onto Murree Rd',
        secondaryInstruction: 'Pass by Rawal Lake entrance on left',
        distanceKm: 4.5,
        distanceText: '4.5 km',
        durationMin: 7.0,
        durationText: '7 mins',
        roadName: 'Murree Rd',
      ),
      const RouteStep(
        maneuver: 'DESTINATION',
        instruction: 'Arrive at Lake View Park',
        primaryInstruction: 'Arrive at Lake View Park',
        distanceKm: 0.2,
        distanceText: '200 m',
        durationMin: 1.0,
        durationText: '1 min',
      ),
    ];

    final sampleRoute = RouteOption(
      id: 'preview_test_route',
      polylinePoints: const [
        LatLng(33.6844, 73.0479),
        LatLng(33.7000, 73.0600),
        LatLng(33.7294, 73.0931),
      ],
      distanceKm: 6.8,
      durationMin: 12.0,
      staticDurationMin: 12.0,
      summary: 'via Jinnah Ave and Murree Rd',
      labels: const ['FASTEST'],
      trafficLevel: 'NORMAL',
      trafficIntervals: const [],
      steps: sampleSteps,
      economics: const RouteEconomics(
        fuelCost: 150,
        maintenanceCost: 40,
        tollCost: 0,
        driverCost: 200,
        riderFare: 550,
        commission: 11,
        driverProfit: 539,
        profitPerMin: 44.9,
      ),
    );

    testWidgets('Tapping direction minimizes sheet to show clicked text and turn card', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewScreen(
            explicitPickup: pickup,
            explicitDropoff: dropoff,
            explicitRoutes: [sampleRoute],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially active turn card is not shown
      expect(find.byKey(const ValueKey('active_step_card')), findsNothing);

      // Locate and tap the second direction item: "Turn right onto Murree Rd"
      final stepFinder = find.text('Turn right onto Murree Rd');
      expect(stepFinder, findsOneWidget);
      await tester.tap(stepFinder);
      await tester.pumpAndSettle();

      // Now the active step card is shown in the minimized sheet
      expect(find.byKey(const ValueKey('active_step_card')), findsOneWidget);
      expect(find.text('TURN 2 OF 3'), findsOneWidget);
      expect(find.text('4.5 km'), findsOneWidget);
      expect(find.textContaining('Pass by Rawal Lake entrance'), findsOneWidget);

      // Tapping "All Turns" expands sheet back to full timeline
      final allTurnsFinder = find.text('All Turns');
      expect(allTurnsFinder, findsOneWidget);
      await tester.tap(allTurnsFinder);
      await tester.pumpAndSettle();

      // Full timeline is visible
      expect(find.text('3 turns'), findsOneWidget);
    });

    test('FirestoreSafetyService createShareLink returns null when backend is uninitialized in test suite', () async {
      final safetyService = FirestoreSafetyService();
      final url = await safetyService.createShareLink('ride_test_share_123');

      expect(url, isNull);
    });
  });
}
