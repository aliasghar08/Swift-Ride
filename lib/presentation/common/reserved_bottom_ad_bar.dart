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
    // 1. Hide immediately if the soft keyboard is open (e.g. typing destination)
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }

    AuthProvider? auth;
    RideProvider? rideProv;

    try {
      auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    } catch (_) {}

    try {
      rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    } catch (_) {}

    // 2. Hide for admin dashboard
    if (auth?.activeRole == UserRole.admin) {
      return const SizedBox.shrink();
    }

    // 3. Emergency SOS: Safety critical, hide ad bar for all users during active SOS
    final isSosActive = rideProv?.activeSos != null;
    if (isSosActive) {
      return const SizedBox.shrink();
    }

    // 4. Driver Mode Visibility Rules:
    // HIDE only while actively driving a trip (in-progress ride).
    // Available on all screens for driver when idle, waiting, or offline.
    if (auth?.activeRole == UserRole.driver) {
      final currentRide = rideProv?.currentRide;
      final hasActiveRide = currentRide != null &&
          currentRide.status != RideStatus.completed &&
          currentRide.status != RideStatus.cancelled;

      if (hasActiveRide) {
        return const SizedBox.shrink();
      }
    }

    // 5. Passenger (Rider) Mode (even during driving!), Driver Idle/Offline, or Unauthenticated/Login:
    // Render reserved 60 dp solid bar.
    final c = Theme.of(context).extension<AppColors>() ??
        (Theme.of(context).brightness == Brightness.dark ? AppColors.dark : AppColors.light);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: barHeight,
        child: Center(
          child: Container(
            key: const Key('reserved_bottom_ad_bar'),
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
    );
  }
}
