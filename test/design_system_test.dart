import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/theme/app_theme.dart';
import 'package:swiftride/core/theme/design_tokens.dart';

void main() {
  group('Design system', () {
    test('both themes register the AppColors extension', () {
      final light = AppTheme.lightTheme.extension<AppColors>();
      final dark = AppTheme.darkTheme.extension<AppColors>();

      expect(light, isNotNull);
      expect(dark, isNotNull);

      // The semantic roles must actually differ between brightnesses, otherwise
      // screens that read them get a light canvas in dark mode.
      expect(light!.canvas, isNot(equals(dark!.canvas)));
      expect(light.textPrimary, isNot(equals(dark.textPrimary)));
      expect(light.border, isNot(equals(dark.border)));
    });

    test('themes carry the bundled Inter family', () {
      expect(AppTheme.fontFamily, 'Inter');
      expect(AppTheme.lightTheme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(AppTheme.darkTheme.textTheme.titleLarge?.fontFamily, 'Inter');
      expect(AppTheme.darkTheme.textTheme.labelSmall?.fontFamily, 'Inter');
    });

    test('scaffold background comes from the canvas token', () {
      expect(
        AppTheme.lightTheme.scaffoldBackgroundColor,
        AppTheme.lightTheme.extension<AppColors>()!.canvas,
      );
      expect(
        AppTheme.darkTheme.scaffoldBackgroundColor,
        AppTheme.darkTheme.extension<AppColors>()!.canvas,
      );
    });

    test('motion tokens are strictly ordered', () {
      expect(Motion.instant < Motion.fast, isTrue);
      expect(Motion.fast < Motion.normal, isTrue);
      expect(Motion.normal < Motion.slow, isTrue);
      expect(Motion.slow < Motion.deliberate, isTrue);
    });

    testWidgets('Motion.resolve honours reduce-motion', (tester) async {
      late Duration reduced;
      late Duration normal;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reduced = Motion.resolve(context, Motion.slow);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              normal = Motion.resolve(context, Motion.slow);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(reduced, Duration.zero);
      expect(normal, Motion.slow);
    });
  });
}
