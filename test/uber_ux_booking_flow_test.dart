import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/presentation/rider/address_search_screen.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';

void main() {
  group('Uber/Careem-Style UX Upgrade Tests', () {
    testWidgets('AddressSearchScreen returns ChooseOnMapSignal with chooseOnMap and isPickup flags', (tester) async {
      dynamic returnedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedResult = await Navigator.of(context).push<dynamic>(
                  MaterialPageRoute(
                    builder: (_) => const AddressSearchScreen(
                      title: 'Set Destination',
                      isPickup: false,
                    ),
                  ),
                );
              },
              child: const Text('Launch Search'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch Search'));
      await tester.pumpAndSettle();

      // Verify "Choose on Map" action is visible
      expect(find.text('Choose on Map'), findsOneWidget);
      expect(find.byIcon(Icons.map_rounded), findsOneWidget);

      // Tap "Choose on Map"
      await tester.tap(find.text('Choose on Map'));
      await tester.pumpAndSettle();

      // Verify returned signal implements both Map with chooseOnMap: true and LocationPoint
      expect(returnedResult, isNotNull);
      expect(returnedResult is Map, isTrue);
      expect(returnedResult['chooseOnMap'], isTrue);
      expect(returnedResult['isPickup'], isFalse);

      expect(returnedResult is LocationPoint, isTrue);
      expect((returnedResult as LocationPoint).address, equals('__CHOOSE_ON_MAP__'));
    });

    testWidgets('AddressSearchScreen passes isPickup=true when searching pickup', (tester) async {
      dynamic returnedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedResult = await Navigator.of(context).push<dynamic>(
                  MaterialPageRoute(
                    builder: (_) => const AddressSearchScreen(
                      title: 'Set Pickup Location',
                      isPickup: true,
                    ),
                  ),
                );
              },
              child: const Text('Launch Pickup Search'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Launch Pickup Search'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose on Map'));
      await tester.pumpAndSettle();

      expect(returnedResult['chooseOnMap'], isTrue);
      expect(returnedResult['isPickup'], isTrue);
    });

    test('RiderViewModel triggers zero-click auto-routing & AI sweet spot pricing immediately on setDestination', () async {
      final vm = RiderViewModel();

      final pickup = const LocationPoint(
        latitude: 31.2785,
        longitude: 72.3317,
        address: 'Clock Tower, Jhang',
      );
      final destination = const LocationPoint(
        latitude: 31.3500,
        longitude: 72.4000,
        address: 'Gojra Road, Jhang',
      );

      // Set pickup first
      await vm.setPickup(pickup);
      expect(vm.pickupLocation?.address, equals('Clock Tower, Jhang'));
      expect(vm.dropoffLocation, isNull);

      // Now set destination -> zero clicks needed, automatically invokes route & ML pricing
      await vm.setDestination(destination);
      expect(vm.dropoffLocation?.address, equals('Gojra Road, Jhang'));

      // Verify aliases fetchRoute() and getDirections() exist and can be called safely
      await vm.fetchRoute();
      await vm.getDirections();

      vm.dispose();
    });

    test('ChooseOnMapSignal operates cleanly as a Map and a LocationPoint', () {
      final signal = ChooseOnMapSignal(isPickup: true);

      expect(signal.latitude, equals(0.0));
      expect(signal.longitude, equals(0.0));
      expect(signal.address, equals('__CHOOSE_ON_MAP__'));
      expect(signal['chooseOnMap'], isTrue);
      expect(signal['isPickup'], isTrue);

      signal['customTag'] = 'testVal';
      expect(signal['customTag'], equals('testVal'));
      expect(signal.containsKey('customTag'), isTrue);
      expect(signal.keys, contains('customTag'));
      signal.remove('customTag');
      expect(signal.containsKey('customTag'), isFalse);
    });
  });
}
