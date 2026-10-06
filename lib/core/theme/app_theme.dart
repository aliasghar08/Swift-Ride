import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'design_tokens.dart';

class AppTheme {
  // ---------------------------------------------------------------- brand
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color darkNavy = Color(0xFF0A1128);
  static const Color primaryNavy = darkNavy;
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color accentTeal = emeraldGreen;
  static const Color sunsetCoral = Color(0xFFEF4444);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color slateMuted = Color(0xFF64748B);

  /// Bundled in assets/fonts (SIL OFL 1.1). Declared so every TextTheme entry
  /// inherits it rather than falling back to the platform default.
  static const String fontFamily = 'Inter';

  // ------------------------------------------------- glassmorphism tokens
  static Color glassLightBackground = Colors.white.withValues(alpha: 0.85);
  static Color glassLightBorder = Colors.white.withValues(alpha: 0.65);
  static Color glassDarkBackground = const Color(0xFF0F172A).withValues(alpha: 0.85);
  static Color glassDarkBorder = const Color(0xFF334155).withValues(alpha: 0.55);

  // ------------------------------------------------------------- elevation
  static List<BoxShadow> get subtleElevation => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get premiumElevation => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: primaryBlue.withValues(alpha: 0.07),
          blurRadius: 28,
          spreadRadius: 2,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get darkElevation => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: accentCyan.withValues(alpha: 0.08),
          blurRadius: 20,
          spreadRadius: -2,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> glowShadow(Color color, {double opacity = 0.35, double blur = 16}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: blur,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
      ];

  // ------------------------------------------------------------- gradients
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, accentCyan],
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A263D), Color(0xFF0E1626)],
  );

  // ---------------------------------------------------------------- themes
  static ThemeData get lightTheme => _build(Brightness.light, AppColors.light);

  static ThemeData get darkTheme => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors c) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: accentCyan,
            secondary: primaryBlue,
            surface: c.surface,
            error: sunsetCoral,
            onPrimary: c.onBrand,
            onSurface: c.textPrimary,
          )
        : ColorScheme.light(
            primary: primaryBlue,
            secondary: accentCyan,
            surface: c.surface,
            error: sunsetCoral,
            onPrimary: c.onBrand,
            onSurface: c.textPrimary,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      primaryColor: isDark ? accentCyan : primaryBlue,
      scaffoldBackgroundColor: c.canvas,
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[c],
      textTheme: _textTheme(c),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: isDark ? 0 : 2,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.lgAll,
          side: isDark ? BorderSide(color: c.border) : BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? accentCyan : primaryBlue,
          foregroundColor: isDark ? darkNavy : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xxl,
            vertical: Spacing.lg,
          ),
          shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xl,
            vertical: Spacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.lg,
        ),
        hintStyle: TextStyle(color: c.textMuted),
        border: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: isDark ? accentCyan : primaryBlue, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: Radii.smAll),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onBrand,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      ),
      // Explicit, consistent page transitions across platforms.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Type scale. Sizes are deliberately few and far between so screens stop
  /// inventing their own.
  static TextTheme _textTheme(AppColors c) {
    TextStyle base(double size, FontWeight weight, {double? height, Color? color}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color ?? c.textPrimary,
        );

    return TextTheme(
      displaySmall: base(32, FontWeight.w700, height: 1.15),
      headlineMedium: base(24, FontWeight.w700, height: 1.2),
      headlineSmall: base(20, FontWeight.w700, height: 1.25),
      titleLarge: base(18, FontWeight.w600, height: 1.3),
      titleMedium: base(16, FontWeight.w600, height: 1.35),
      titleSmall: base(14, FontWeight.w600, height: 1.35),
      bodyLarge: base(16, FontWeight.w400, height: 1.45, color: c.textSecondary),
      bodyMedium: base(14, FontWeight.w400, height: 1.45, color: c.textSecondary),
      bodySmall: base(12.5, FontWeight.w400, height: 1.4, color: c.textMuted),
      labelLarge: base(14, FontWeight.w600, height: 1.2),
      labelMedium: base(12, FontWeight.w600, height: 1.2, color: c.textMuted),
      labelSmall: base(11, FontWeight.w600, height: 1.2, color: c.textMuted),
    );
  }
}
