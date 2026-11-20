import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A premium, hardware-accelerated frosted glass container using [BackdropFilter]
/// with gradient highlights, layered shadows, and subtle border refraction.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final bool? isDark;
  final Gradient? gradient;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.blur = 16.0,
    this.backgroundColor,
    this.borderColor,
    this.shadows,
    this.isDark,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final themeIsDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedIsDark = isDark ?? themeIsDark;
    // Bypass BackdropFilter on Android to prevent EGL/FBO framebuffer readback deadlocks
    // when compositing FlutterOverlaySurface over hardware PlatformViews (Google Maps) on Mali GPUs.
    final useBlur = blur > 0 && defaultTargetPlatform != TargetPlatform.android;
    final effectiveBg = backgroundColor ??
        (useBlur
            ? (resolvedIsDark ? AppTheme.glassDarkBackground : AppTheme.glassLightBackground)
            : (resolvedIsDark ? const Color(0xF0141B2D) : const Color(0xF5FFFFFF)));
    final effectiveBorder = borderColor ??
        (resolvedIsDark ? AppTheme.glassDarkBorder : AppTheme.glassLightBorder);
    final effectiveShadows = shadows ??
        (resolvedIsDark ? AppTheme.darkElevation : AppTheme.premiumElevation);

    final innerContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: effectiveBorder,
          width: 1.2,
        ),
        gradient: gradient ??
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: resolvedIsDark
                  ? [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.01),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.65),
                      Colors.white.withValues(alpha: 0.25),
                    ],
            ),
      ),
      child: child,
    );

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: effectiveShadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: useBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: innerContent,
              )
            : innerContent,
      ),
    );
  }
}
