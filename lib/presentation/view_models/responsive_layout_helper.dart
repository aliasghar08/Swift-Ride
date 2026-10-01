import 'dart:math';
import 'package:flutter/widgets.dart';

enum ScreenType {
  compactPhone,
  standardPhone,
  tablet,
  desktop;

  bool get isCompact => this == ScreenType.compactPhone;
  bool get isTabletOrDesktop => this == ScreenType.tablet || this == ScreenType.desktop;
}

/// Pixel-perfect responsive screen adapter that provides dynamic scaling,
/// breakpoint detection, and safe layout metrics for all form factors.
class ResponsiveLayoutHelper {
  final BuildContext context;
  late final double screenWidth;
  late final double screenHeight;
  late final double textScale;
  late final EdgeInsets safePadding;
  late final ScreenType screenType;

  ResponsiveLayoutHelper(this.context) {
    final media = MediaQuery.of(context);
    screenWidth = media.size.width;
    screenHeight = media.size.height;
    textScale = media.textScaler.scale(1.0);
    safePadding = media.padding;

    if (screenWidth < 360) {
      screenType = ScreenType.compactPhone;
    } else if (screenWidth < 600) {
      screenType = ScreenType.standardPhone;
    } else if (screenWidth < 1024) {
      screenType = ScreenType.tablet;
    } else {
      screenType = ScreenType.desktop;
    }
  }

  /// Scale size relative to standard 390pt mobile design width.
  double scale(double size) {
    if (screenType.isTabletOrDesktop) {
      return size * 1.15;
    }
    final ratio = screenWidth / 390.0;
    // Clamp to prevent extreme shrinking on small screens
    return size * max(0.85, min(1.2, ratio));
  }

  /// Calculates responsive font size.
  double fontSize(double baseSize) {
    final scaled = scale(baseSize);
    return max(10.0, scaled / textScale);
  }

  /// Ensures minimum 48px touch target height for mobile ergonomics (WCAG compliant).
  double touchTarget(double preferredHeight) {
    return max(48.0, preferredHeight);
  }

  /// Responsive horizontal padding for sheets and containers.
  double get horizontalPadding {
    switch (screenType) {
      case ScreenType.compactPhone:
        return 12.0;
      case ScreenType.standardPhone:
        return 16.0;
      case ScreenType.tablet:
        return 32.0;
      case ScreenType.desktop:
        return 48.0;
    }
  }

  /// Responsive card max width for larger screens.
  double get maxCardWidth {
    if (screenWidth > 600) return 560.0;
    return screenWidth;
  }
}
