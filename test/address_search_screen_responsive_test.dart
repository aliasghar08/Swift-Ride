import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/presentation/common/reserved_bottom_ad_bar.dart';
import 'package:swiftride/presentation/rider/address_search_screen.dart';
import 'package:swiftride/providers/location_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({
    required Size size,
    EdgeInsets viewInsets = EdgeInsets.zero,
    double textScale = 1.0,
    bool isPickup = false,
  }) {
    final locationProvider = LocationProvider();

    return CustomChangeNotifierProvider<LocationProvider>(
      notifier: locationProvider,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            viewInsets: viewInsets,
            textScaler: TextScaler.linear(textScale),
          ),
          child: AddressSearchScreen(
            title: isPickup ? 'Set Pickup Location' : 'Set Destination',
            isPickup: isPickup,
          ),
        ),
      ),
    );
  }

  group('AddressSearchScreen Responsive & Keyboard Overflow Tests', () {
    testWidgets('Compact phone viewport with active soft keyboard has ZERO overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Simulate compact phone screen with active keyboard (320px bottom inset)
      await tester.pumpWidget(
        buildTestWidget(
          size: const Size(360, 640),
          viewInsets: const EdgeInsets.only(bottom: 320),
          isPickup: true,
        ),
      );
      await tester.pumpAndSettle();

      // Verify zero overflow exception thrown
      expect(tester.takeException(), isNull);

      // Verify search input, Choose on Map, and quick action options are present
      expect(find.text('Set Pickup Location'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Choose on Map'), findsOneWidget);
      expect(find.text('Use Current Location'), findsOneWidget);
      expect(find.text('Set Location on Map'), findsOneWidget);
      expect(find.text('Type a destination or area name'), findsOneWidget);

      // Bottom ad slot must stay hidden while keyboard is open
      expect(find.byType(ReservedBottomAdBar), findsNothing);

      // Verify content can be dragged/scrolled without overflow
      await tester.drag(find.text('Choose on Map'), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Extremely small phone (320x568) with 280px keyboard has ZERO overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          size: const Size(320, 568),
          viewInsets: const EdgeInsets.only(bottom: 280),
          isPickup: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Choose on Map'), findsOneWidget);
      expect(find.text('Type a destination or area name'), findsOneWidget);
      expect(find.byType(ReservedBottomAdBar), findsNothing);
    });

    testWidgets('Large tablet viewport constrains max content width and renders bottom ad bar', (tester) async {
      tester.view.physicalSize = const Size(1024, 1366);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          size: const Size(1024, 1366),
          viewInsets: EdgeInsets.zero,
          isPickup: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Bottom ad slot is shown when keyboard is closed
      expect(find.byType(ReservedBottomAdBar), findsOneWidget);

      // Verify max width constraint (constrained to 640px)
      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.byType(ConstrainedBox),
      );
      final hasTabletMaxWidth = constrainedBoxes.any(
        (box) => box.constraints.maxWidth == 640.0,
      );
      expect(hasTabletMaxWidth, isTrue);

      // Verify all quick action items are present
      expect(find.text('Choose on Map'), findsOneWidget);
      expect(find.text('Use Current Location'), findsOneWidget);
      expect(find.text('Set Location on Map'), findsOneWidget);
      expect(find.text('Type a destination or area name'), findsOneWidget);
    });

    testWidgets('Large text scale factor (1.5x accessibility) with keyboard has ZERO overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          size: const Size(390, 844),
          viewInsets: const EdgeInsets.only(bottom: 340),
          textScale: 1.5,
          isPickup: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Choose on Map'), findsOneWidget);
      expect(find.text('Type a destination or area name'), findsOneWidget);
    });
  });
}
