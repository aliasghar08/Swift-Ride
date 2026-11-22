import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';

/// Glassmorphic credibility and status dialog displayed whenever a driver
/// toggles Online or Offline.
///
/// Builds captain trust by transparently explaining background dispatch,
/// adaptive battery optimization, and fare transparency.
class DriverStatusCredibilityDialog extends StatelessWidget {
  final bool isGoingOnline;

  const DriverStatusCredibilityDialog({
    super.key,
    required this.isGoingOnline,
  });

  /// Displays the credibility dialog and returns `true` if the driver confirmed,
  /// or `false` / `null` if cancelled.
  static Future<bool?> show(
    BuildContext context, {
    required bool isGoingOnline,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: isGoingOnline,
      builder: (ctx) => DriverStatusCredibilityDialog(
        isGoingOnline: isGoingOnline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final headerIcon = isGoingOnline
        ? Icons.radar_rounded
        : Icons.pause_circle_filled_rounded;
    final headerColor = isGoingOnline
        ? const Color(0xFF10B981) // Emerald green
        : const Color(0xFFF59E0B); // Amber warning

    final title = isGoingOnline
        ? "You're Online & Ready for Offers"
        : 'Go Offline & Pause Offers?';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: Radii.xlAll,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 580),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF131A2A).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.95),
              borderRadius: Radii.xlAll,
              border: Border.all(
                color: headerColor.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: headerColor.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Header Icon Badge
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: headerColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: headerColor.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      headerIcon,
                      size: 34,
                      color: headerColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Dialog Title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),

                // Bullet Items
                if (isGoingOnline) ...[
                  _buildBulletRow(
                    context,
                    icon: Icons.notifications_active_rounded,
                    iconColor: const Color(0xFF38BDF8), // Sky blue
                    title: 'Works Even When Closed',
                    description:
                        'Instant ride offer alerts & sound arrive even if you close or swipe Swift Ride away—until you manually toggle OFF.',
                  ),
                  const SizedBox(height: 14),
                  _buildBulletRow(
                    context,
                    icon: Icons.battery_saver_rounded,
                    iconColor: const Color(0xFF10B981), // Emerald green
                    title: 'Battery-Smart Standby',
                    description:
                        'Low-power GPS mode protects your battery while waiting for nearby passengers.',
                  ),
                  const SizedBox(height: 14),
                  _buildBulletRow(
                    context,
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: const Color(0xFFF59E0B), // Amber
                    title: '98% Earnings Guarantee',
                    description:
                        'Keep 98% of every trip fare (2% fee) with live OGRA fuel & net profit transparency on every offer.',
                  ),
                  const SizedBox(height: 14),
                  _buildBulletRow(
                    context,
                    icon: Icons.power_settings_new_rounded,
                    iconColor: const Color(0xFFA855F7), // Purple
                    title: 'Full Control',
                    description:
                        'Switch off anytime from the app toggle or your status-bar notification.',
                  ),
                ] else ...[
                  _buildBulletRow(
                    context,
                    icon: Icons.notifications_off_rounded,
                    iconColor: const Color(0xFFEF4444), // Red
                    title: 'No Ride Alerts',
                    description:
                        'You will not receive incoming passenger offers while the app is open or closed.',
                  ),
                  const SizedBox(height: 14),
                  _buildBulletRow(
                    context,
                    icon: Icons.location_off_rounded,
                    iconColor: const Color(0xFFF59E0B), // Amber
                    title: 'GPS Completely Stopped',
                    description:
                        'Background location updates and dispatch listeners are turned off.',
                  ),
                  const SizedBox(height: 14),
                  _buildBulletRow(
                    context,
                    icon: Icons.replay_rounded,
                    iconColor: const Color(0xFF64748B), // Slate
                    title: 'Manual Resume',
                    description:
                        'You will stay Offline until you manually switch back ON.',
                  ),
                ],

                const SizedBox(height: 24),

                // Action Buttons
                if (isGoingOnline)
                  FilledButton(
                    key: const Key('driver_credibility_got_it_btn'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Got It',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('driver_credibility_stay_online_btn'),
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: c.textMuted.withValues(alpha: 0.3),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
                          ),
                          child: Text(
                            'Stay Online',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const Key('driver_credibility_confirm_offline_btn'),
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: Radii.mdAll),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Confirm Go Offline',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildBulletRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    final c = AppColors.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: c.textSecondary,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
