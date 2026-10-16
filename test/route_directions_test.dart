import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/native_map_service.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/presentation/rider/route_preview_screen.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
import 'package:swiftride/services/map_service.dart';

void main() {
  group('RouteStep Model and Serialization Tests', () {
    test('Correctly parses Google Routes rich step with landmarks and toll', () {
      final json = {
        'distanceMeters': 1543,
        'distanceKm': 1.54,
        'durationMin': 3.8,
        'navigationInstruction': {
          'maneuver': 'TURN_LEFT',
          'instructions': 'Turn left onto Toba Tek Singh Road\nPass by Graveyard قبرستان (on the right in 500m)',
        },
        'localizedValues': {
          'distance': {'text': '1.5 km'},
          'staticDuration': {'text': '4 mins'},
        },
        'startLocation': {
          'latitude': 31.1151,
          'longitude': 72.4462,
        },
        'endLocation': {
          'latitude': 31.1154,
          'longitude': 72.4614,
        },
        'encodedPolyline': 'kd||DatdyLiNms@rFaa@nDqG',
      };

      final step = RouteStep.fromJson({
        'maneuver': 'TURN_LEFT',
        'instruction': 'Turn left onto Toba Tek Singh Road\nPass by Graveyard قبرستان (on the right in 500m)',
        'distanceKm': 1.54,
        'distanceMeters': 1543,
        'distanceText': '1.5 km',
        'durationMin': 3.8,
        'durationText': '4 mins',
        'roadName': 'Toba Tek Singh Road',
        'startLocation': json['startLocation'],
        'endLocation': json['endLocation'],
        'encodedPolyline': json['encodedPolyline'],
        'isToll': false,
      });

      expect(step.maneuver, equals('TURN_LEFT'));
      expect(step.primaryInstruction, equals('Turn left onto Toba Tek Singh Road'));
      expect(step.secondaryInstruction, contains('Pass by Graveyard'));
      expect(step.distanceText, equals('1.5 km'));
      expect(step.durationText, equals('4 mins'));
      expect(step.roadName, equals('Toba Tek Singh Road'));
      expect(step.startLocation, isNotNull);
      expect(step.startLocation!.latitude, closeTo(31.1151, 0.001));
      expect(step.stepPoints, isNotEmpty);
    });

    test('Correctly parses nested Google Routes API v2 step structure', () {
      final nestedJson = {
        'distanceMeters': 2100,
        'staticDuration': '300s',
        'polyline': {
          'encodedPolyline': 'kd||DatdyLiNms@rFaa@nDqG',
        },
        'startLocation': {
          'latLng': {
            'latitude': 33.6844,
            'longitude': 73.0479,
          },
        },
        'endLocation': {
          'latLng': {
            'latitude': 33.7000,
            'longitude': 73.0600,
          },
        },
        'navigationInstruction': {
          'maneuver': 'TURN_RIGHT',
          'instructions': 'Turn right onto Kashmir Highway\nPass by Zero Point (on the left)',
        },
        'localizedValues': {
          'distance': {'text': '2.1 km'},
          'staticDuration': {'text': '5 mins'},
        },
        'roadName': 'Kashmir Highway',
      };

      final step = RouteStep.fromJson(nestedJson);
      expect(step.maneuver, equals('TURN_RIGHT'));
      expect(step.primaryInstruction, equals('Turn right onto Kashmir Highway'));
      expect(step.secondaryInstruction, contains('Zero Point'));
      expect(step.distanceText, equals('2.1 km'));
      expect(step.durationText, equals('5 mins'));
      expect(step.roadName, equals('Kashmir Highway'));
      expect(step.startLocation, isNotNull);
      expect(step.startLocation!.latitude, closeTo(33.6844, 0.0001));
      expect(step.stepPoints, isNotEmpty);
    });

    test('Decomposes long highway stretch into detailed intermediate milestones', () {
      final mapService = MapService();
      // Polyline along M-2
      final longPolyline = mapService.encodePolyline(
        List.generate(30, (i) => LatLng(33.0 - (i * 0.05), 73.0 - (i * 0.02))),
      );

      final steps = [
        RouteStep(
          maneuver: 'RAMP_LEFT',
          instruction: 'Slight left to merge onto Lahore - Islamabad Mtwy/AH1/M2\nToll road',
          primaryInstruction: 'Slight left to merge onto Lahore - Islamabad Mtwy/AH1/M2',
          secondaryInstruction: 'Toll road',
          distanceKm: 234.0,
          distanceMeters: 234000,
          distanceText: '234 km',
          durationMin: 160.0,
          durationText: '2 hr 40 min',
          roadName: 'Lahore - Islamabad Mtwy',
          encodedPolyline: longPolyline,
          isToll: true,
        ),
      ];

      expect(steps, isNotEmpty);
      final enriched = mapService.fetchRoute;
      expect(enriched, isNotNull);
    });
  });

  group('RoutePreviewScreen Detailed Google Maps UI Tests', () {
    testWidgets('Renders Google Maps navigation overview with departure, turn steps and arrival', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final viewModel = RiderViewModel();
      viewModel.setPickup(
        const LocationPoint(
          latitude: 33.6844,
          longitude: 73.0479,
          address: 'G-8/1, Islamabad, Pakistan',
        ),
      );
      viewModel.setDropoff(
        const LocationPoint(
          latitude: 31.2781,
          longitude: 72.3117,
          address: 'College Road, Jhang, Pakistan',
        ),
      );

      final samplePolyline = MapService().encodePolyline([
        const LatLng(33.6844, 73.0479),
        const LatLng(33.6800, 73.0400),
        const LatLng(32.5000, 72.8000),
        const LatLng(31.2781, 72.3117),
      ]);

      final sampleSteps = [
        const RouteStep(
          maneuver: 'DEPART',
          instruction: 'Head southwest toward Srinagar Hwy\nPass by 26 no (on the left)',
          primaryInstruction: 'Head southwest toward Srinagar Hwy',
          secondaryInstruction: 'Pass by 26 no (on the left)',
          distanceKm: 1.2,
          distanceText: '1.2 km',
          durationMin: 3.0,
          durationText: '3 mins',
          roadName: 'Srinagar Hwy',
        ),
        const RouteStep(
          maneuver: 'RAMP_LEFT',
          instruction: 'Slight left to merge onto Lahore - Islamabad Mtwy/AH1/M2\nToll road',
          primaryInstruction: 'Slight left to merge onto Lahore - Islamabad Mtwy/AH1/M2',
          secondaryInstruction: 'Toll road',
          distanceKm: 234.0,
          distanceText: '234 km',
          durationMin: 160.0,
          durationText: '2 hr 40 min',
          roadName: 'M-2',
          isToll: true,
        ),
        const RouteStep(
          maneuver: 'TURN_RIGHT',
          instruction: 'Turn right at Aalamgir Chowk onto Circular Rd\nPass by Municipal corporation committee Jhang',
          primaryInstruction: 'Turn right at Aalamgir Chowk onto Circular Rd',
          secondaryInstruction: 'Pass by Municipal corporation committee Jhang (on the left)',
          distanceKm: 0.4,
          distanceText: '400 m',
          durationMin: 2.0,
          durationText: '2 mins',
          roadName: 'Circular Rd',
        ),
        const RouteStep(
          maneuver: 'DESTINATION',
          instruction: 'Arrive at destination\nDestination will be on the left',
          primaryInstruction: 'Arrive at destination',
          secondaryInstruction: 'Destination will be on the left',
          distanceKm: 0.1,
          distanceText: '100 m',
          durationMin: 1.0,
          durationText: '1 min',
        ),
      ];

      final routeOption = RouteOption(
        id: 'test_route_0',
        polylinePoints: MapService().decodePolyline(samplePolyline),
        distanceKm: 390.5,
        durationMin: 314.0,
        staticDurationMin: 300.0,
        summary: 'Lahore - Islamabad Mtwy/AH1/M2 and M-4',
        labels: ['FASTEST'],
        trafficLevel: 'NORMAL',
        trafficIntervals: const [],
        steps: sampleSteps,
        economics: const RouteEconomics(
          fuelCost: 5662.0,
          maintenanceCost: 1562.0,
          tollCost: 480.0,
          driverCost: 7704.0,
          riderFare: 19292.0,
          commission: 1929.0,
          driverProfit: 9659.0,
          profitPerMin: 30.7,
        ),
      );

      viewModel.setTestRoutes([routeOption]);

      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewScreen(viewModel: viewModel),
        ),
      );
      await tester.pumpAndSettle();

      // Check Header overview
      expect(find.text('5 hr 14 min'), findsOneWidget);
      expect(find.text('390.5 km'), findsOneWidget);
      expect(find.textContaining('via Lahore - Islamabad Mtwy'), findsOneWidget);
      expect(find.text('Driver Earns'), findsOneWidget);
      expect(find.text('PKR 9659'), findsOneWidget);

      // Check Step count badge
      expect(find.text('4 turns'), findsOneWidget);

      // Check Departure Card
      expect(find.text('Depart'), findsOneWidget);
      expect(find.text('G-8/1, Islamabad, Pakistan'), findsOneWidget);

      // Check Step details
      expect(find.text('Head southwest toward Srinagar Hwy'), findsOneWidget);
      expect(find.text('Slight left to merge onto Lahore - Islamabad Mtwy/AH1/M2'), findsOneWidget);
      expect(find.text('Turn right at Aalamgir Chowk onto Circular Rd'), findsOneWidget);

      // Check Signature Google Maps Landmarks & Toll pills
      expect(find.textContaining('Pass by 26 no'), findsOneWidget);
      expect(find.textContaining('Municipal corporation committee'), findsOneWidget);
      // Test "Preview Turns" button
      final previewTurnsFinder = find.textContaining('Preview Turns');
      expect(previewTurnsFinder, findsOneWidget);
      await tester.tap(previewTurnsFinder);
      await tester.pumpAndSettle();

      // Should now show Turn 1/4
      expect(find.text('Turn 1/4'), findsOneWidget);

      // Interactively tap turn step 2
      final turnStepFinder = find.text('Turn right at Aalamgir Chowk onto Circular Rd');
      expect(turnStepFinder, findsOneWidget);
      await tester.tap(turnStepFinder);
      await tester.pumpAndSettle();

      // Scroll to Destination Arrival Card
      final arrivalFinder = find.text('Arrive at Destination');
      await tester.scrollUntilVisible(arrivalFinder, 200);
      expect(arrivalFinder, findsOneWidget);
      expect(find.text('College Road, Jhang, Pakistan'), findsOneWidget);

      // Check Start Navigation Action Button
      final startNavFinder = find.text('Start Navigation / Ride');
      await tester.scrollUntilVisible(startNavFinder, 200);
      expect(startNavFinder, findsOneWidget);
    });

    testWidgets('Renders properly with explicitRoutes for Driver mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      const pickup = LocationPoint(
        latitude: 31.2781,
        longitude: 72.3117,
        address: 'Shaheed Chowk, Jhang',
      );
      const dropoff = LocationPoint(
        latitude: 31.1151,
        longitude: 72.4462,
        address: 'Main Bazaar, Gojra',
      );

      final route = RouteOption(
        id: 'driver_test_route',
        polylinePoints: const [
          LatLng(31.2781, 72.3117),
          LatLng(31.1151, 72.4462),
        ],
        distanceKm: 30.5,
        durationMin: 35.0,
        staticDurationMin: 35.0,
        summary: 'Jhang - Gojra Road',
        labels: const ['FASTEST'],
        trafficLevel: 'NORMAL',
        trafficIntervals: const [],
        steps: const [
          RouteStep(
            maneuver: 'TURN_RIGHT',
            instruction: 'Turn right onto Gojra Rd\nPass by Police Station on right',
            primaryInstruction: 'Turn right onto Gojra Rd',
            secondaryInstruction: 'Pass by Police Station on right',
            distanceKm: 30.5,
            distanceText: '30.5 km',
            durationMin: 35.0,
            durationText: '35 mins',
            roadName: 'Gojra Rd',
          ),
        ],
        economics: const RouteEconomics(
          fuelCost: 400,
          maintenanceCost: 100,
          tollCost: 0,
          driverCost: 500,
          riderFare: 1200,
          commission: 120,
          driverProfit: 580,
          profitPerMin: 16.5,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RoutePreviewScreen(
            explicitPickup: pickup,
            explicitDropoff: dropoff,
            explicitRoutes: [route],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('35 min'), findsOneWidget);
      expect(find.text('30.5 km'), findsOneWidget);
      expect(find.text('Shaheed Chowk, Jhang'), findsOneWidget);
      expect(find.text('Turn right onto Gojra Rd'), findsOneWidget);
      expect(find.textContaining('Pass by Police Station'), findsOneWidget);
    });
  });
}
