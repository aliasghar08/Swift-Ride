import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/presentation/view_models/responsive_layout_helper.dart';

void main() {
  /// Builds a helper under a specific screen width and text scale.
  Future<ResponsiveLayoutHelper> helperFor(
    WidgetTester tester, {
    required double width,
    required double textScale,
  }) async {
    late ResponsiveLayoutHelper helper;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Builder(
          builder: (context) {
            helper = ResponsiveLayoutHelper(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return helper;
  }

  group('ResponsiveLayoutHelper.fontSize', () {
    testWidgets('does not shrink when the user enlarges text', (tester) async {
      final normal = await helperFor(tester, width: 390, textScale: 1.0);
      final enlarged = await helperFor(tester, width: 390, textScale: 2.0);

      // Regression guard: fontSize used to divide by the text scale, so a rider
      // who asked for 2x text got text at half the design size — the exact
      // opposite of the accessibility setting.
      expect(
        enlarged.fontSize(16),
        equals(normal.fontSize(16)),
        reason: 'fontSize must return an unscaled size; Flutter applies the '
            'user text scale to TextStyle.fontSize itself.',
      );
    });

    testWidgets('stays proportional to the design width', (tester) async {
      final phone = await helperFor(tester, width: 390, textScale: 1.0);
      final tablet = await helperFor(tester, width: 900, textScale: 1.0);

      expect(tablet.fontSize(16), greaterThan(phone.fontSize(16)));
    });

    testWidgets('never returns an unusably small size', (tester) async {
      final tiny = await helperFor(tester, width: 320, textScale: 1.0);
      expect(tiny.fontSize(4), greaterThanOrEqualTo(10.0));
    });
  });

  group('ResponsiveLayoutHelper.touchTarget', () {
    testWidgets('enforces the 48dp minimum tap target', (tester) async {
      final helper = await helperFor(tester, width: 390, textScale: 1.0);

      expect(helper.touchTarget(20), 48.0);
      expect(helper.touchTarget(64), 64.0);
    });
  });
}
