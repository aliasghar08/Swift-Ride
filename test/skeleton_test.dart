import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/theme/app_theme.dart';
import 'package:swiftride/presentation/common/skeleton.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  group('Skeleton', () {
    testWidgets('shimmer is suppressed when reduce-motion is on', (tester) async {
      await pump(
        tester,
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SkeletonBox(height: 20),
        ),
      );

      expect(find.byType(SkeletonBox), findsOneWidget);

      // Reduce-motion renders a flat block; the animated gradient is absent.
      final box = tester.widget<Container>(
        find.descendant(of: find.byType(SkeletonBox), matching: find.byType(Container)).first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, isNotNull);
    });

    testWidgets('animates when motion is allowed', (tester) async {
      await pump(
        tester,
        const MediaQuery(
          data: MediaQueryData(disableAnimations: false),
          child: SkeletonBox(height: 20),
        ),
      );

      final box = tester.widget<Container>(
        find.descendant(of: find.byType(SkeletonBox), matching: find.byType(Container)).first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.gradient, isNotNull);
    });

    testWidgets('SkeletonList renders the requested number of cards', (tester) async {
      await pump(tester, const SkeletonList(count: 3));

      expect(find.byType(SkeletonCard), findsNWidgets(3));
    });
  });
}
