import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../presentation/../../presentation/common/glass_container.dart';
import '../../presentation/../../presentation/common/staggered_animation.dart';

class SafetyCheckOverlay extends StatelessWidget {
  final String rideId;
  final String flagType;
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback onNeedHelp;

  const SafetyCheckOverlay({
    super.key,
    required this.rideId,
    required this.flagType,
    required this.message,
    required this.onDismiss,
    required this.onNeedHelp,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StaggeredEntryWidget(
      index: 0,
      duration: const Duration(milliseconds: 300),
      slideOffset: -20.0,
      child: GlassContainer(
        isDark: isDark,
        borderRadius: 20,
        padding: const EdgeInsets.all(16),
        borderColor: Colors.amber.withValues(alpha: 0.6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.amber.withValues(alpha: 0.2),
                  AppTheme.glassDarkBackground,
                ]
              : [
                  Colors.amber.shade50.withValues(alpha: 0.95),
                  Colors.white.withValues(alpha: 0.9),
                ],
        ),
        shadows: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PulsingGlowWidget(
                  glowColor: Colors.amber,
                  minSpread: 2.0,
                  maxSpread: 6.0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.amber,
                    ),
                    child: const Icon(
                      Icons.shield,
                      size: 16,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _flagTitle(flagType),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                  ),
                ),
                const Spacer(),
                Text(
                  'RideCheck AI',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDismiss,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: isDark ? Colors.white38 : AppTheme.primaryNavy.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "I'm OK",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.primaryNavy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onNeedHelp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Need Help',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _flagTitle(String flag) {
    switch (flag) {
      case 'LONG_STOP':
      case 'UNEXPECTED_STOP':
        return 'UNEXPECTED STOP DETECTED';
      case 'ROUTE_DEVIATION':
        return 'ROUTE DEVIATION DETECTED';
      default:
        return 'SAFETY CHECK-IN';
    }
  }
}
