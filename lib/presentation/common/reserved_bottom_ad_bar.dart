import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/design_tokens.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ride_provider.dart';
import '../../services/ad_service.dart';
import 'ad_banner_widget.dart';

/// A reserved bottom ad slot that sits outside the map [PlatformView] surface.
///
/// Ensures zero hardware layer overlap with Google Maps on Mali GPUs (Infinix, Xiaomi),
/// prevents layout jumps by reserving an explicit, unobstructed bar, and strictly hides
/// during active driving for drivers, emergency SOS, or when the keyboard is open.
class ReservedBottomAdBar extends StatelessWidget {
  const ReservedBottomAdBar({super.key});

  /// The reserved height for the bottom ad slot (50 dp banner + 10 dp padding/border).
  static const double barHeight = 60.0;

  @override
  Widget build(BuildContext context) {
    AuthProvider? auth;
    RideProvider? rideProv;

    try {
      auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    } catch (_) {}

    try {
      rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    } catch (_) {}

    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final bottomInset = mediaQuery.padding.bottom;

    // Evaluate centralized visibility policy
    final policyAllows = AdVisibilityPolicy.shouldShowAds(
      role: auth?.activeRole,
      tripStatus: rideProv?.currentRide?.status,
      isNavigationActive: rideProv?.isNavigationActive ?? false,
      isSosActive: rideProv?.activeSos != null,
    );

    final shouldHide = isKeyboardOpen || !policyAllows;

    final c = Theme.of(context).extension<AppColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? AppColors.dark : AppColors.light);

    // Reserved explicit height includes system safe area inset so banner is never clipped to < 50dp
    final totalHeight = barHeight + bottomInset;

    return SizedBox(
      height: shouldHide ? 0.0 : totalHeight,
      child: Offstage(
        offstage: shouldHide,
        child: Container(
          key: const Key('reserved_bottom_ad_bar'),
          height: totalHeight,
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(
              top: BorderSide(color: c.border, width: 1.0),
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: SizedBox(
              height: barHeight,
              child: const Center(
                child: AdBannerWidget(
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
