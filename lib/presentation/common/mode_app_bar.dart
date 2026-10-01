import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../view_models/responsive_layout_helper.dart';
import 'staggered_animation.dart';

class ModeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const ModeAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final isDark = auth.activeRole == UserRole.driver;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.85),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155).withValues(alpha: 0.5)
                      : const Color(0xFFE2E8F0).withValues(alpha: 0.8),
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
              padding: EdgeInsets.symmetric(horizontal: layout.scale(9), vertical: 5),
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: AppTheme.glowShadow(AppTheme.primaryBlue, opacity: 0.3, blur: 12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car, color: Colors.white, size: layout.scale(16)),
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
                  border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.4)),
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
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                  : const Color(0xFFF1F5F9).withValues(alpha: 0.8),
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
      ],
    );
  }

  Widget _buildRoleButton({
    required ResponsiveLayoutHelper layout,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: layout.scale(8), vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? AppTheme.glowShadow(AppTheme.primaryBlue, opacity: 0.35, blur: 8)
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
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.slateMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
