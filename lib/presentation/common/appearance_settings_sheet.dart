import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/theme_provider.dart';

/// Modal bottom sheet allowing users to customize their visual theme preset
/// and UI layout density live with instantaneous preview and persistent storage.
class AppearanceSettingsSheet extends StatelessWidget {
  const AppearanceSettingsSheet({super.key});

  /// Displays the Appearance & Interface picker modal sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => const AppearanceSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final themeProv = CustomChangeNotifierProvider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
            maxWidth: 600,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F172A).withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: c.border.withValues(alpha: isDark ? 0.4 : 0.8),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: c.textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Header Row with Title and Reset Action
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.palette_rounded, color: c.info, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Appearance & Interface',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Visual theme presets & layout density',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const Key('appearance_reset_defaults_btn'),
                      onPressed: () => themeProv.resetToDefault(),
                      style: TextButton.styleFrom(
                        foregroundColor: c.info,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: Visual Theme
                      _buildSectionHeader(
                        context,
                        title: 'Visual Theme',
                        subtitle: 'Color aesthetic & surface palette',
                        icon: Icons.brush_rounded,
                      ),
                      const SizedBox(height: 12),
                      _buildThemeCard(
                        context,
                        preset: SwiftThemePreset.obsidianGlass,
                        name: 'Obsidian Glass',
                        description: 'Deep midnight slate & electric cyan glow',
                        badgeText: 'Default • Most Popular',
                        swatches: [
                          const Color(0xFF0B1120),
                          const Color(0xFF131D31),
                          const Color(0xFF00E5FF),
                        ],
                        selected: themeProv.preset == SwiftThemePreset.obsidianGlass,
                        onTap: () => themeProv.setPreset(SwiftThemePreset.obsidianGlass),
                      ),
                      const SizedBox(height: 10),
                      _buildThemeCard(
                        context,
                        preset: SwiftThemePreset.daylightPearl,
                        name: 'Daylight Pearl',
                        description: 'Crisp alabaster, deep cobalt & clean slate',
                        swatches: [
                          const Color(0xFFF8FAFC),
                          Colors.white,
                          const Color(0xFF1D4ED8),
                        ],
                        selected: themeProv.preset == SwiftThemePreset.daylightPearl,
                        onTap: () => themeProv.setPreset(SwiftThemePreset.daylightPearl),
                      ),
                      const SizedBox(height: 10),
                      _buildThemeCard(
                        context,
                        preset: SwiftThemePreset.amoledPitch,
                        name: 'AMOLED Pitch Black',
                        description: 'True #000000 OLED black with neon telemetry',
                        swatches: [
                          Colors.black,
                          const Color(0xFF0F0F10),
                          const Color(0xFF00E5FF),
                        ],
                        selected: themeProv.preset == SwiftThemePreset.amoledPitch,
                        onTap: () => themeProv.setPreset(SwiftThemePreset.amoledPitch),
                      ),
                      const SizedBox(height: 10),
                      _buildThemeCard(
                        context,
                        preset: SwiftThemePreset.emeraldGold,
                        name: 'Royal Emerald Gold',
                        description: 'Deep forest slate with champagne gold accents',
                        swatches: [
                          const Color(0xFF071A15),
                          const Color(0xFF0E2E25),
                          const Color(0xFFF59E0B),
                        ],
                        selected: themeProv.preset == SwiftThemePreset.emeraldGold,
                        onTap: () => themeProv.setPreset(SwiftThemePreset.emeraldGold),
                      ),

                      const SizedBox(height: 24),

                      // Section 2: Interface Layout Style
                      _buildSectionHeader(
                        context,
                        title: 'Interface Layout Style',
                        subtitle: 'UI spacing, card density & accessibility',
                        icon: Icons.dashboard_customize_rounded,
                      ),
                      const SizedBox(height: 12),
                      _buildLayoutModeCard(
                        context,
                        mode: SwiftUiLayoutMode.modernFloating,
                        name: 'Modern Floating Glass',
                        badgeText: 'Default',
                        description:
                            'Full-bleed map with floating glass sheets (r=24) and balanced blur.',
                        icon: Icons.layers_rounded,
                        selected: themeProv.layoutMode == SwiftUiLayoutMode.modernFloating,
                        onTap: () => themeProv.setLayoutMode(SwiftUiLayoutMode.modernFloating),
                      ),
                      const SizedBox(height: 10),
                      _buildLayoutModeCard(
                        context,
                        mode: SwiftUiLayoutMode.compactCockpit,
                        name: 'Compact Pro Cockpit',
                        description:
                            'Condense card padding with dense telemetry metrics visible at a glance.',
                        icon: Icons.view_compact_rounded,
                        selected: themeProv.layoutMode == SwiftUiLayoutMode.compactCockpit,
                        onTap: () => themeProv.setLayoutMode(SwiftUiLayoutMode.compactCockpit),
                      ),
                      const SizedBox(height: 10),
                      _buildLayoutModeCard(
                        context,
                        mode: SwiftUiLayoutMode.easyRead,
                        name: 'Easy Read (High-Contrast)',
                        description:
                            'Larger touch targets (56dp), +15% scaled text, and solid opaque cards with blur disabled.',
                        icon: Icons.text_fields_rounded,
                        selected: themeProv.layoutMode == SwiftUiLayoutMode.easyRead,
                        onTap: () => themeProv.setLayoutMode(SwiftUiLayoutMode.easyRead),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final c = AppColors.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: c.info),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeCard(
    BuildContext context, {
    required SwiftThemePreset preset,
    required String name,
    required String description,
    required List<Color> swatches,
    required bool selected,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = c.info;

    return InkWell(
      key: Key('theme_card_${preset.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: isDark ? 0.12 : 0.08)
              : c.surfaceRaised.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? activeColor : c.border.withValues(alpha: 0.5),
            width: selected ? 2.0 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Color swatches indicator
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: swatches
                    .map(
                      (color) => Container(
                        width: 14,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 0.8,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(width: 14),

            // Theme details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: activeColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: activeColor.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: activeColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Selection Checkmark
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? activeColor : Colors.transparent,
                border: Border.all(
                  color: selected ? activeColor : c.textMuted.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutModeCard(
    BuildContext context, {
    required SwiftUiLayoutMode mode,
    required String name,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = c.info;

    return InkWell(
      key: Key('layout_card_${mode.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: isDark ? 0.12 : 0.08)
              : c.surfaceRaised.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? activeColor : c.border.withValues(alpha: 0.5),
            width: selected ? 2.0 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: (selected ? activeColor : c.textMuted).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? activeColor : c.textSecondary,
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
                          name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: activeColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: activeColor.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: activeColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? activeColor : Colors.transparent,
                border: Border.all(
                  color: selected ? activeColor : c.textMuted.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
