import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ride_provider.dart';
import 'ad_banner_widget.dart';

/// A reserved bottom ad slot that sits outside the map [PlatformView] surface.
///
/// Ensures zero hardware layer overlap with Google Maps on Mali GPUs (Infinix, Xiaomi),
/// prevents layout jumps by reserving a solid 60 dp bar, and strictly hides
/// during active driving for drivers, emergency SOS, or when the
/// keyboard is open.
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

    // 1. Soft keyboard open
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    // 2. Admin dashboard
    final isAdmin = auth?.activeRole == UserRole.admin;

    // 3. Emergency SOS: safety critical, hide ad bar for all users during active SOS
    final isSosActive = rideProv?.activeSos != null;

    // 4. Driver Mode: HIDE only while actively driving a trip
    bool isDriverActivelyDriving = false;
    if (auth?.activeRole == UserRole.driver) {
      final currentRide = rideProv?.currentRide;
      if (currentRide != null &&
          currentRide.status != RideStatus.completed &&
          currentRide.status != RideStatus.cancelled) {
        isDriverActivelyDriving = true;
      }
    }

    // 5. PhoneAuthScreen is open / unauthenticated state
    final isPhoneAuthOpen = (auth != null && auth.signOutGeneration > 0 && !auth.isAuthenticated);

    final shouldHide = isKeyboardOpen ||
        isAdmin ||
        isSosActive ||
        isDriverActivelyDriving ||
        isPhoneAuthOpen;

    final c = Theme.of(context).extension<AppColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? AppColors.dark : AppColors.light);

    return SizedBox(
      height: shouldHide ? 0.0 : barHeight,
      child: Offstage(
        offstage: shouldHide,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: barHeight,
            child: Center(
              child: Container(
                key: shouldHide ? null : const Key('reserved_bottom_ad_bar'),
                height: barHeight,
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 600),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(
                    top: BorderSide(color: c.border, width: 1.0),
                  ),
                ),
                child: const Center(
                  child: AdBannerWidget(
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
