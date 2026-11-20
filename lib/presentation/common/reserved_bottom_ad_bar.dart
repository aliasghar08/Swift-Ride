import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/ride_provider.dart';
import 'ad_banner_widget.dart';

/// A reserved bottom ad slot that sits outside the map [PlatformView] surface.
///
/// Ensures zero hardware layer overlap with Google Maps on Mali GPUs (Infinix, Xiaomi),
/// prevents layout jumps by reserving a solid 60 dp bar, and strictly hides
/// during active driving, driver online status, emergency SOS, or when the
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
    DriverProvider? driverProv;
    RideProvider? rideProv;

    try {
      auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    } catch (_) {}

    try {
      driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    } catch (_) {}

    try {
      rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    } catch (_) {}

    // 2. Hide for unauthenticated users, auth login step, or admin dashboard
    if (auth == null || !auth.isAuthenticated || auth.activeRole == UserRole.admin) {
      return const SizedBox.shrink();
    }

    // 3. Driver Mode Visibility Rules:
    // HIDE if driver is Online OR has an active ride / incoming request / SOS active
    if (auth.activeRole == UserRole.driver) {
      final isOnline = driverProv?.isOnline ?? false;
      final currentRide = rideProv?.currentRide;
      final hasActiveRide = currentRide != null &&
          currentRide.status != RideStatus.completed &&
          currentRide.status != RideStatus.cancelled;
      final isSosActive = rideProv?.activeSos != null;

      if (isOnline || hasActiveRide || isSosActive) {
        return const SizedBox.shrink();
      }
    }

    // 4. Passenger (Rider) Mode OR Driver Offline: Render reserved 60 dp solid bar
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF141B2D) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000);

    return SafeArea(
      top: false,
      child: Container(
        key: const Key('reserved_bottom_ad_bar'),
        height: barHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            top: BorderSide(color: borderColor, width: 1.0),
          ),
        ),
        child: const Center(
          child: AdBannerWidget(
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
