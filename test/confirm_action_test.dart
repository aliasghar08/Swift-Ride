import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/theme/app_theme.dart';
import 'package:swiftride/presentation/common/confirm_action.dart';

void main() {
  /// Pumps a button that invokes confirmAction and records its result.
  Future<List<bool>> pumpAndRun(WidgetTester tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: 'Cancel this ride?',
                  message: 'This cannot be undone.',
                  confirmLabel: 'Cancel ride',
                  cancelLabel: 'Keep ride',
                  destructive: true,
                );
                results.add(ok);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    return results;
  }

  testWidgets('confirmAction resolves false when the user cancels', (tester) async {
    final results = await pumpAndRun(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this ride?'), findsOneWidget);

    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  testWidgets('confirmAction resolves true only on explicit confirmation', (tester) async {
    final results = await pumpAndRun(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel ride'));
    await tester.pumpAndSettle();

    expect(results, [true]);
  });
}
