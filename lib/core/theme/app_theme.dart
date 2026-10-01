import 'package:flutter/material.dart';

class AppTheme {
  // Brand Color Palette
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color darkNavy = Color(0xFF0A1128);
  static const Color primaryNavy = darkNavy;
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color accentTeal = emeraldGreen;
  static const Color sunsetCoral = Color(0xFFEF4444);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color slateMuted = Color(0xFF64748B);

  // Premium Glassmorphism & Elevation Tokens
  static Color glassLightBackground = Colors.white.withValues(alpha: 0.85);
  static Color glassLightBorder = Colors.white.withValues(alpha: 0.65);
  static Color glassDarkBackground = const Color(0xFF0F172A).withValues(alpha: 0.85);
  static Color glassDarkBorder = const Color(0xFF334155).withValues(alpha: 0.55);

  // Multi-layered Soft Shadows
  static List<BoxShadow> get subtleElevation {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ];
  }

  static List<BoxShadow> get premiumElevation {
    return [
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
  }

  static List<BoxShadow> get darkElevation {
    return [
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
  }

  static List<BoxShadow> glowShadow(Color color, {double opacity = 0.35, double blur = 16}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: 1,
        offset: const Offset(0, 4),
      ),
    ];
  }

  // Premium Gradients
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

  // Light Theme (Optimized for Rider)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: accentCyan,
        surface: Colors.white,
        error: sunsetCoral,
        onPrimary: Colors.white,
        onSurface: Color(0xFF0F172A),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
        bodyLarge: TextStyle(
          color: Color(0xFF334155),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
      ),
    );
  }

  // Dark Theme (Optimized for Driver night mode)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: accentCyan,
      scaffoldBackgroundColor: const Color(0xFF0B0F19),
      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
        secondary: primaryBlue,
        surface: Color(0xFF131D31),
        error: sunsetCoral,
        onPrimary: Color(0xFF0B0F19),
        onSurface: Color(0xFFF1F5F9),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF131D31),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentCyan,
          foregroundColor: const Color(0xFF0A1128),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF162036),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentCyan, width: 2),
        ),
      ),
    );
  }
}
