import 'package:flutter/material.dart';

/// Spacing scale on a 4pt baseline.
///
/// Screens previously used bare literals (`16`, `13`, `18`) inconsistently.
/// Using the scale keeps rhythm consistent and makes intent obvious.
abstract final class Spacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double massive = 56;

  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets card = EdgeInsets.all(lg);
  static const EdgeInsets cardTight = EdgeInsets.all(md);
  static const EdgeInsets chip = EdgeInsets.symmetric(
    horizontal: sm,
    vertical: xs,
  );
}

/// Corner radii, replacing scattered `BorderRadius.circular(12)` calls.
abstract final class Radii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double sheet = 28;
  static const double pill = 999;

  static BorderRadius get xsAll => BorderRadius.circular(xs);
  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get sheetTop =>
      const BorderRadius.vertical(top: Radius.circular(sheet));
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

/// Motion tokens. Durations stay short: this is a task-driven app, not a demo.
abstract final class Motion {
  /// Tap feedback — must feel instant.
  static const Duration instant = Duration(milliseconds: 90);

  /// Small state changes: chips, icons, colour transitions.
  static const Duration fast = Duration(milliseconds: 180);

  /// Default for most transitions.
  static const Duration normal = Duration(milliseconds: 260);

  /// Sheets, page transitions, larger surfaces.
  static const Duration slow = Duration(milliseconds: 420);

  /// Deliberate, attention-carrying motion (arrival, SOS).
  static const Duration deliberate = Duration(milliseconds: 650);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve entrance = Curves.easeOutBack;

  /// Respects the platform's reduce-motion setting.
  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : duration;
}

/// Semantic colour roles resolved per brightness.
///
/// Registered as a [ThemeExtension] so widgets read intent
/// (`AppColors.of(context).textPrimary`) instead of a hex literal that silently
/// drifts from the palette.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;

  /// Slightly raised surface for pills, chips, avatars and inline rows.
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color onBrand;

  /// Translucent chrome over the map (sheets, pills, icon buttons).
  final Color mapChrome;
  final Color mapChromeStrong;

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.onBrand,
    required this.mapChrome,
    required this.mapChromeStrong,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  static const AppColors light = AppColors(
    canvas: Color(0xFFF8FAFC),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF1F5F9),
    surfaceRaised: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textMuted: Color(0xFF64748B),
    onBrand: Colors.white,
    mapChrome: Color(0xD9FFFFFF),
    mapChromeStrong: Colors.white,
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF2563EB),
  );

  static const AppColors dark = AppColors(
    canvas: Color(0xFF0B0F19),
    surface: Color(0xFF131D31),
    surfaceMuted: Color(0xFF162036),
    surfaceRaised: Color(0xFF1E293B),
    border: Color(0xFF1E293B),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    onBrand: Color(0xFF0A1128),
    mapChrome: Color(0xE00F172A),
    mapChromeStrong: Color(0xFF0B0F19),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF00E5FF),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceRaised,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? onBrand,
    Color? mapChrome,
    Color? mapChromeStrong,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      onBrand: onBrand ?? this.onBrand,
      mapChrome: mapChrome ?? this.mapChrome,
      mapChromeStrong: mapChromeStrong ?? this.mapChromeStrong,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      mapChrome: Color.lerp(mapChrome, other.mapChrome, t)!,
      mapChromeStrong: Color.lerp(mapChromeStrong, other.mapChromeStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
