import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../view_models/responsive_layout_helper.dart';
import 'staggered_animation.dart';
import 'trusted_contacts_screen.dart';
import 'legal_terms_modal.dart';
import 'ai_consent_dialog.dart';
import '../auth/phone_auth_screen.dart';

class ModeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const ModeAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(62);

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
      automaticallyImplyLeading: false,
      toolbarHeight: 62,
      titleSpacing: 0,
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
      title: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final isWide = maxW >= 500;
          final isCompact = maxW < 370;

          final brandPill = Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 7 : 9,
              vertical: isWide ? 5 : 3.5,
            ),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(9),
              boxShadow: AppTheme.glowShadow(
                AppTheme.primaryBlue,
                opacity: 0.3,
                blur: 10,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_car,
                  color: Colors.white,
                  size: isCompact ? 13 : 15,
                ),
                const SizedBox(width: 5),
                Text(
                  'SwiftRide',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isCompact ? 12.5 : 14,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          );

          final feeBadge = PulsingGlowWidget(
            glowColor: AppTheme.emeraldGreen,
            minSpread: 1.0,
            maxSpread: 3.5,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 5 : 7,
                vertical: isWide ? 3 : 1.5,
              ),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '2% Fee (Always)',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: AppTheme.emeraldGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: isCompact ? 8.5 : 9.5,
                ),
              ),
            ),
          );

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 10),
            child: Row(
              children: [
                // Adaptive Brand + 2% Fee Header Block (never clipped)
                Flexible(
                  fit: FlexFit.tight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: isWide
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                brandPill,
                                const SizedBox(width: 8),
                                feeBadge,
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                brandPill,
                                const SizedBox(height: 2.5),
                                feeBadge,
                              ],
                            ),
                    ),
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 6),
                // Role Switcher Segmented Control
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRoleButton(
                        layout: layout,
                        label: 'Rider',
                        icon: Icons.person,
                        isSelected: auth.activeRole == UserRole.rider,
                        isCompact: isCompact,
                        onTap: () => auth.switchRole(UserRole.rider),
                      ),
                      _buildRoleButton(
                        layout: layout,
                        label: 'Driver',
                        icon: Icons.drive_eta,
                        isSelected: auth.activeRole == UserRole.driver,
                        isCompact: isCompact,
                        onTap: () => auth.switchRole(UserRole.driver),
                      ),
                      _buildRoleButton(
                        layout: layout,
                        label: 'Admin',
                        icon: Icons.dashboard,
                        isSelected: auth.activeRole == UserRole.admin,
                        isCompact: isCompact,
                        onTap: () => auth.switchRole(UserRole.admin),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 6),
                // Auth / User Profile Icon Button
                InkWell(
                  onTap: () => _showUserSessionModal(context, auth, isDark, layout),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: EdgeInsets.all(isCompact ? 5.5 : 7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.surfaceRaised,
                      border: Border.all(
                        color: (auth.isAuthenticated || auth.currentUser.phone.isNotEmpty)
                            ? AppTheme.emeraldGreen
                            : c.border,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      (auth.isAuthenticated || auth.currentUser.phone.isNotEmpty)
                          ? Icons.account_circle
                          : Icons.login,
                      size: isCompact ? 16 : 18,
                      color: (auth.isAuthenticated || auth.currentUser.phone.isNotEmpty)
                          ? AppTheme.emeraldGreen
                          : (isDark ? Colors.white70 : AppTheme.darkNavy),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final user = auth.currentUser;
        final isUserSignedIn = auth.isAuthenticated || user.phone.isNotEmpty;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SingleChildScrollView(
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.fullName.isNotEmpty ? user.fullName : 'SwiftRide User',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: layout.fontSize(17),
                                    color: isDark ? Colors.white : AppTheme.darkNavy,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _showEditProfileDialog(context, auth);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: isDark ? Colors.white60 : AppTheme.primaryBlue,
                                  ),
                                ),
                              ),
                            ],
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
                          if (user.email != null && user.email!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              user.email!,
                              style: TextStyle(
                                fontSize: layout.fontSize(12),
                                color: AppTheme.slateMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
                    Icons.manage_accounts_outlined,
                    color: AppTheme.primaryBlue,
                  ),
                  title: const Text(
                    'Edit Profile Info',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Update your name, phone number, or optional email',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditProfileDialog(context, auth);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.phone_iphone,
                    color: AppTheme.primaryBlue,
                  ),
                  title: Text(
                    isUserSignedIn
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
                    PhoneAuthScreen.navigate(context, replace: true);
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
                if (isUserSignedIn)
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
                ListTile(
                  leading: const Icon(
                    Icons.gavel_rounded,
                    color: AppTheme.primaryBlue,
                  ),
                  title: const Text(
                    'Terms of Service & Legal',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Non-carrier status & permanent 2% fee policy',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    LegalTermsModal.showTerms(context);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppTheme.accentTeal,
                  ),
                  title: const Text(
                    'Privacy & Data Policy',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'PECA 2016 compliance & GPS tracking consent',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    LegalTermsModal.showPrivacy(context);
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: AiConsentDialog.consentNotifier,
                  builder: (tileCtx, aiConsentGranted, _) {
                    return SwitchListTile(
                      key: const Key('profile_ai_consent_switch'),
                      secondary: const Icon(
                        Icons.auto_awesome_outlined,
                        color: AppTheme.primaryBlue,
                      ),
                      title: const Text(
                        'AI Assistant Data Sharing',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        aiConsentGranted
                            ? 'Allowed: sharing prompts & trip context with Google Gemini AI'
                            : 'Declined: cloud AI disabled (core on-device pricing active)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: aiConsentGranted,
                      activeThumbColor: AppTheme.emeraldGreen,
                      onChanged: (val) async {
                        if (val) {
                          await AiConsentDialog.ensureConsent(ctx);
                        } else {
                          await AiConsentDialog.setConsent(false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'AI Assistant Data Sharing revoked. Cloud AI is now disabled.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
                ListTile(
                  key: const Key('session_sign_out_tile'),
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppTheme.sunsetCoral,
                  ),
                  title: const Text(
                    'Sign Out',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.sunsetCoral,
                    ),
                  ),
                  subtitle: Text(
                    isUserSignedIn
                        ? 'Log out of ${user.phone.isNotEmpty ? user.phone : "current session"}'
                        : 'Return to login / sign up screen',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    final navigator = Navigator.of(context, rootNavigator: true);
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    Navigator.pop(ctx);
                    await auth.signOut();
                    messenger?.clearSnackBars();
                    messenger?.showSnackBar(
                      const SnackBar(
                        content: Text('Signed out successfully.'),
                        backgroundColor: AppTheme.emeraldGreen,
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    navigator.pushAndRemoveUntil(
                      AppRouter.smoothRoute(
                        const PhoneAuthScreen(),
                        settings: const RouteSettings(name: '/login'),
                      ),
                      (route) => false,
                    );
                  },
                ),
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
                    'Permanently erase your SwiftRide account & all data',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    _confirmDeleteAccount(context, auth);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  void _showEditProfileDialog(BuildContext context, AuthProvider auth) {
    final user = auth.currentUser;
    final nameCtrl = TextEditingController(
      text: user.fullName == 'Guest User' ? '' : user.fullName,
    );
    final phoneCtrl = TextEditingController(text: user.phone);
    final emailCtrl = TextEditingController(text: user.email ?? '');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.manage_accounts_rounded, color: AppTheme.primaryBlue, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Edit Profile Info',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter your full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+923001234567',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newName = nameCtrl.text.trim();
                final newPhone = phoneCtrl.text.trim();
                final newEmail = emailCtrl.text.trim();
                Navigator.pop(dialogCtx);
                await auth.updateUserProfile(
                  fullName: newName.isNotEmpty ? newName : null,
                  phone: newPhone.isNotEmpty ? newPhone : null,
                  email: newEmail,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profile updated successfully.'),
                      backgroundColor: AppTheme.emeraldGreen,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
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
        final navigator = Navigator.of(context, rootNavigator: true);
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Deleting your account and data...'),
            duration: Duration(seconds: 2),
          ),
        );
        final success = await auth.deleteAccount();
        messenger?.clearSnackBars();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Your SwiftRide account has been permanently deleted.'
                  : (auth.authError ?? 'Failed to delete account. Please re-login and try again.'),
            ),
            backgroundColor: success ? AppTheme.emeraldGreen : Colors.redAccent,
          ),
        );
        if (success) {
          navigator.pushAndRemoveUntil(
            AppRouter.smoothRoute(
              const PhoneAuthScreen(),
              settings: const RouteSettings(name: '/login'),
            ),
            (route) => false,
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
    bool isCompact = false,
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
                horizontal: isCompact ? 5 : 7,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: isCompact ? 11.5 : 13,
                    color: isSelected ? Colors.white : AppTheme.slateMuted,
                  ),
                  SizedBox(width: isCompact ? 2.5 : 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: isCompact ? 10 : 11,
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
