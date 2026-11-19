import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/presentation/common/prominent_disclosure_dialog.dart';

void main() {
  Widget host(Future<bool> Function() onContinue, void Function(bool) onDone) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await ProminentDisclosureDialog.show(
                  context,
                  icon: Icons.location_on,
                  title: 'Allow Location Access',
                  message: PermissionDisclosures.foregroundLocationMessage,
                  onContinue: onContinue,
                );
                onDone(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  group('Google Play Prominent Disclosure', () {
    testWidgets('"Continue" immediately invokes the OS permission request',
        (tester) async {
      var osPromptCalls = 0;
      bool? result;
      await tester.pumpWidget(host(() async {
        osPromptCalls++;
        return true;
      }, (r) => result = r));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prominent_disclosure_dialog')), findsOneWidget);
      expect(find.text(PermissionDisclosures.foregroundLocationMessage),
          findsOneWidget);
      expect(osPromptCalls, 0, reason: 'OS prompt must not fire before consent');

      await tester.tap(find.byKey(const Key('prominent_disclosure_continue')));
      await tester.pumpAndSettle();

      expect(osPromptCalls, 1);
      expect(result, isTrue);
      expect(find.byKey(const Key('prominent_disclosure_dialog')), findsNothing);
    });

    testWidgets('"Not Now" dismisses without launching the OS prompt',
        (tester) async {
      var osPromptCalls = 0;
      bool? result;
      await tester.pumpWidget(host(() async {
        osPromptCalls++;
        return true;
      }, (r) => result = r));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prominent_disclosure_not_now')));
      await tester.pumpAndSettle();

      expect(osPromptCalls, 0);
      expect(result, isFalse);
    });

    testWidgets('Dialog is not dismissible by tapping outside', (tester) async {
      await tester.pumpWidget(host(() async => true, (_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prominent_disclosure_dialog')), findsOneWidget);
    });

    test('Foreground disclosure copy matches Play wording', () {
      expect(
        PermissionDisclosures.foregroundLocationMessage,
        contains('collects your location data'),
      );
      expect(
        PermissionDisclosures.foregroundLocationMessage,
        contains('while using the app'),
      );
    });

    test('Background disclosure copy contains critical mandatory policy phrase', () {
      expect(
        PermissionDisclosures.backgroundLocationMessage,
        contains('even when the app is closed or not in use'),
      );
      expect(
        PermissionDisclosures.backgroundLocationMessage,
        contains('real-time trip navigation'),
      );
    });
  });
}

