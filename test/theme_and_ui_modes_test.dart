import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/core/theme/theme_provider.dart';
import 'package:swiftride/presentation/common/appearance_settings_sheet.dart';
import 'package:swiftride/services/native/native_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeProvider Unit Tests', () {
    late NativeStorageService storage;
    late ThemeProvider themeProv;

    setUp(() async {
      storage = NativeStorageService();
      await storage.remove(ThemeProvider.keyThemePreset);
      await storage.remove(ThemeProvider.keyUiLayoutMode);
      themeProv = ThemeProvider(storage: storage);
    });

    test('Defaults to Obsidian Glass + Modern Floating Glass', () {
      expect(themeProv.preset, equals(SwiftThemePreset.obsidianGlass));
      expect(themeProv.layoutMode, equals(SwiftUiLayoutMode.modernFloating));
      expect(themeProv.isDarkMode, isTrue);
      expect(themeProv.mapStyleJson, contains('#0b1120'));

      final colors = themeProv.appColors;
      expect(colors.glassBlurSigma, equals(16.0));
      expect(colors.cardRadius, equals(24.0));
      expect(colors.buttonMinHeight, equals(50.0));
      expect(colors.isBlurEnabled, isTrue);
    });

    test('Switching visual presets updates theme tokens and map styles', () async {
      // 1. Daylight Pearl
      await themeProv.setPreset(SwiftThemePreset.daylightPearl);
      expect(themeProv.preset, equals(SwiftThemePreset.daylightPearl));
      expect(themeProv.isDarkMode, isFalse);
      expect(themeProv.themeData.brightness, equals(Brightness.light));
      expect(themeProv.mapStyleJson, contains('#f8fafc'));

      // 2. AMOLED Pitch Black
      await themeProv.setPreset(SwiftThemePreset.amoledPitch);
      expect(themeProv.preset, equals(SwiftThemePreset.amoledPitch));
      expect(themeProv.isDarkMode, isTrue);
      expect(themeProv.themeData.scaffoldBackgroundColor, equals(const Color(0xFF000000)));
      expect(themeProv.mapStyleJson, contains('#000000'));

      // 3. Royal Emerald Gold
      await themeProv.setPreset(SwiftThemePreset.emeraldGold);
      expect(themeProv.preset, equals(SwiftThemePreset.emeraldGold));
      expect(themeProv.isDarkMode, isTrue);
      expect(themeProv.themeData.scaffoldBackgroundColor, equals(const Color(0xFF071A15)));
      expect(themeProv.mapStyleJson, contains('#071a15'));
    });

    test('Switching UI layout modes adjusts density, scaling, and blur', () async {
      // 1. Compact Cockpit
      await themeProv.setLayoutMode(SwiftUiLayoutMode.compactCockpit);
      expect(themeProv.layoutMode, equals(SwiftUiLayoutMode.compactCockpit));
      expect(themeProv.appColors.cardRadius, equals(14.0));
      expect(themeProv.appColors.buttonMinHeight, equals(44.0));
      expect(themeProv.appColors.glassBlurSigma, equals(12.0));
      expect(themeProv.appColors.isBlurEnabled, isTrue);

      // 2. Easy Read (High-Contrast)
      await themeProv.setLayoutMode(SwiftUiLayoutMode.easyRead);
      expect(themeProv.layoutMode, equals(SwiftUiLayoutMode.easyRead));
      expect(themeProv.appColors.cardRadius, equals(16.0));
      expect(themeProv.appColors.buttonMinHeight, equals(56.0));
      expect(themeProv.appColors.glassBlurSigma, equals(0.0)); // Blur disabled
      expect(themeProv.appColors.isBlurEnabled, isFalse);
      expect(themeProv.appColors.contentScale, equals(1.15)); // +15% scaled
    });

    test('Reset to default restores Obsidian Glass + Modern Floating', () async {
      await themeProv.setPreset(SwiftThemePreset.daylightPearl);
      await themeProv.setLayoutMode(SwiftUiLayoutMode.easyRead);
      expect(themeProv.preset, equals(SwiftThemePreset.daylightPearl));
      expect(themeProv.layoutMode, equals(SwiftUiLayoutMode.easyRead));

      await themeProv.resetToDefault();
      expect(themeProv.preset, equals(SwiftThemePreset.obsidianGlass));
      expect(themeProv.layoutMode, equals(SwiftUiLayoutMode.modernFloating));
      expect(themeProv.isDarkMode, isTrue);
    });
  });

  group('AppearanceSettingsSheet Widget Tests', () {
    late NativeStorageService storage;
    late ThemeProvider themeProv;

    setUp(() async {
      storage = NativeStorageService();
      await storage.remove(ThemeProvider.keyThemePreset);
      await storage.remove(ThemeProvider.keyUiLayoutMode);
      themeProv = ThemeProvider(storage: storage);
    });

    testWidgets('Renders all theme preset & layout mode cards and allows switching', (tester) async {
      await tester.pumpWidget(
        CustomChangeNotifierProvider<ThemeProvider>(
          notifier: themeProv,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => AppearanceSettingsSheet.show(ctx),
                  child: const Text('Open Appearance'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Appearance'));
      await tester.pumpAndSettle();

      expect(find.text('Appearance & Interface'), findsOneWidget);
      expect(find.text('Visual Theme'), findsOneWidget);
      expect(find.text('Interface Layout Style'), findsOneWidget);

      // Presets
      expect(find.byKey(const Key('theme_card_obsidianGlass')), findsOneWidget);
      expect(find.byKey(const Key('theme_card_daylightPearl')), findsOneWidget);
      expect(find.byKey(const Key('theme_card_amoledPitch')), findsOneWidget);
      expect(find.byKey(const Key('theme_card_emeraldGold')), findsOneWidget);

      // Tap Daylight Pearl
      await tester.tap(find.byKey(const Key('theme_card_daylightPearl')));
      await tester.pumpAndSettle();
      expect(themeProv.preset, equals(SwiftThemePreset.daylightPearl));

      // Scroll and Tap Easy Read mode
      await tester.ensureVisible(find.byKey(const Key('layout_card_easyRead')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_card_easyRead')));
      await tester.pumpAndSettle();
      expect(themeProv.layoutMode, equals(SwiftUiLayoutMode.easyRead));

      // Tap Reset button
      await tester.ensureVisible(find.byKey(const Key('appearance_reset_defaults_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance_reset_defaults_btn')));
      await tester.pumpAndSettle();

      expect(themeProv.preset, equals(SwiftThemePreset.obsidianGlass));
      expect(themeProv.layoutMode, equals(SwiftUiLayoutMode.modernFloating));
    });
  });
}
