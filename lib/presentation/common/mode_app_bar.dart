import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../view_models/responsive_layout_helper.dart';
import 'staggered_animation.dart';
import 'trusted_contacts_screen.dart';
import '../auth/phone_auth_screen.dart';

class ModeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const ModeAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    // Derive brightness from the active theme, not from the user's role. Other
    // widgets in this app read Theme.of(context).brightness, so deriving it from
    // the role here made the app bar disagree with its own contents.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: c.mapChrome,
              border: Border(
                bottom: BorderSide(
                  color: c.border.withValues(alpha: isDark ? 0.5 : 0.8),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: layout.scale(9),
                vertical: 5,
              ),
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: AppTheme.glowShadow(
                  AppTheme.primaryBlue,
                  opacity: 0.3,
                  blur: 12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: layout.scale(16),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SwiftRide',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: layout.fontSize(15),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Zero-commission Badge with pulsing glow
            PulsingGlowWidget(
              glowColor: AppTheme.emeraldGreen,
              minSpread: 1.0,
              maxSpread: 4.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '0% Fee (Year 1)',
                  style: TextStyle(
                    color: AppTheme.emeraldGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: layout.fontSize(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Role Switcher Dropdown / Segmented control
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: c.surfaceRaised.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04),
              ),
            ),
            child: Row(
              children: [
                _buildRoleButton(
                  layout: layout,
                  label: 'Rider',
                  icon: Icons.person,
                  isSelected: auth.activeRole == UserRole.rider,
                  onTap: () => auth.switchRole(UserRole.rider),
                ),
                _buildRoleButton(
                  layout: layout,
                  label: 'Driver',
                  icon: Icons.drive_eta,
                  isSelected: auth.activeRole == UserRole.driver,
                  onTap: () => auth.switchRole(UserRole.driver),
                ),
                _buildRoleButton(
                  layout: layout,
                  label: 'Admin',
                  icon: Icons.dashboard,
                  isSelected: auth.activeRole == UserRole.admin,
                  onTap: () => auth.switchRole(UserRole.admin),
                ),
              ],
            ),
          ),
        ),
        // Auth / User Profile Icon Button
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: InkWell(
            onTap: () => _showUserSessionModal(context, auth, isDark, layout),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surfaceRaised,
                border: Border.all(
                  color: auth.isAuthenticated
                      ? AppTheme.emeraldGreen
                      : c.border,
                  width: 1.5,
                ),
              ),
              child: Icon(
                auth.isAuthenticated ? Icons.account_circle : Icons.login,
                size: layout.scale(18),
                color: auth.isAuthenticated
                    ? AppTheme.emeraldGreen
                    : (isDark ? Colors.white70 : AppTheme.darkNavy),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showUserSessionModal(
    BuildContext context,
    AuthProvider auth,
    bool isDark,
    ResponsiveLayoutHelper layout,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final user = auth.currentUser;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(layout.scale(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: layout.scale(24),
                      backgroundColor: AppTheme.primaryBlue.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        user.fullName.isNotEmpty
                            ? user.fullName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: layout.fontSize(17),
                              color: isDark ? Colors.white : AppTheme.darkNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.phone.isNotEmpty
                                ? user.phone
                                : 'Not verified with phone',
                            style: TextStyle(
                              fontSize: layout.fontSize(13),
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star,
                            color: AppTheme.amberWarning,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            user.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: AppTheme.emeraldGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(
                    Icons.phone_iphone,
                    color: AppTheme.primaryBlue,
                  ),
                  title: Text(
                    auth.isAuthenticated
                        ? 'Switch / Re-login Phone'
                        : 'Sign In with Phone (OTP)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Authenticate using Firebase SMS verification',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PhoneAuthScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.history_rounded,
                    color: AppTheme.primaryBlue,
                  ),
                  title: const Text(
                    'Trip & Ride History',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'View past rides, route locations, and receipts',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/history');
                  },
                ),
                if (auth.isAuthenticated)
                  ListTile(
                    leading: const Icon(
                      Icons.health_and_safety_outlined,
                      color: AppTheme.emeraldGreen,
                    ),
                    title: const Text(
                      'Trusted Contacts',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      user.trustedContacts.isEmpty
                          ? 'Nobody is notified if you trigger SOS'
                          : '${user.trustedContacts.length} contact'
                                '${user.trustedContacts.length == 1 ? '' : 's'} notified on SOS',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TrustedContactsScreen(),
                        ),
                      );
                    },
                  ),
                if (auth.isAuthenticated)
                  ListTile(
                    leading: const Icon(
                      Icons.logout,
                      color: AppTheme.sunsetCoral,
                    ),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.sunsetCoral,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await auth.signOut();
                    },
                  ),
                if (auth.isAuthenticated) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'Delete Account',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                    subtitle: const Text(
                      'Permanently erase your SwiftRide account & data',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      _confirmDeleteAccount(context, auth);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context, AuthProvider auth) {
    showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delete Account?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to permanently delete your SwiftRide account?\n\n'
            '• All your personal profile data, ride history, and active sessions will be permanently erased.\n'
            '• This action cannot be undone.\n\n'
            'In compliance with Apple Privacy Guidelines, all associated cloud records will be purged.',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Delete Permanently'),
            ),
          ],
        );
      },
    ).then((confirmed) async {
      if (confirmed == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deleting your account and data...'),
            duration: Duration(seconds: 2),
          ),
        );
        final success = await auth.deleteAccount();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Your SwiftRide account has been permanently deleted.'
                    : (auth.authError ?? 'Failed to delete account. Please re-login and try again.'),
              ),
              backgroundColor: success ? AppTheme.emeraldGreen : Colors.redAccent,
            ),
          );
        }
      }
    });
  }

  Widget _buildRoleButton({
    required ResponsiveLayoutHelper layout,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    // Semantics.tooltip is used instead of a nested Tooltip widget: the nested
    // tooltip contributes its own semantics node, which replaced this label and
    // left the control announced incorrectly.
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label mode',
      tooltip: 'Switch to $label mode',
      // The visible word is redundant once the role is announced, and leaving it
      // in would merge into the label ("Rider mode Rider").
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        // Meets the 48dp minimum touch target (WCAG 2.5.5). The visual pill
        // stays compact; only the tappable area grows.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: layout.scale(8),
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: isSelected
                    ? AppTheme.glowShadow(
                        AppTheme.primaryBlue,
                        opacity: 0.35,
                        blur: 8,
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: layout.scale(13),
                    color: isSelected ? Colors.white : AppTheme.slateMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: layout.fontSize(11),
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected ? Colors.white : AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
