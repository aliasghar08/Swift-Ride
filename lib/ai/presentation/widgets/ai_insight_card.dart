import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../domain/ai_insight.dart';
import '../../presentation/../../presentation/common/glass_container.dart';
import '../../presentation/../../presentation/common/staggered_animation.dart';

class AiInsightCard extends StatelessWidget {
  final AiInsight insight;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  const AiInsightCard({
    super.key,
    required this.insight,
    this.onRefresh,
    this.isRefreshing = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recs = insight.recommendations;

    return StaggeredEntryWidget(
      index: 0,
      duration: const Duration(milliseconds: 380),
      child: GlassContainer(
        isDark: isDark,
        borderRadius: 22,
        padding: const EdgeInsets.all(18),
        borderColor: AppTheme.accentTeal.withValues(alpha: 0.35),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppTheme.accentTeal.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.03),
                ]
              : [
                  Colors.white.withValues(alpha: 0.95),
                  AppTheme.accentTeal.withValues(alpha: 0.06),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    PulsingGlowWidget(
                      glowColor: AppTheme.accentTeal,
                      minSpread: 1.0,
                      maxSpread: 4.0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentTeal.withValues(alpha: 0.2),
                        ),
                        child: const Icon(
                          Icons.psychology,
                          size: 18,
                          color: AppTheme.accentTeal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _insightTitle(insight.type),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppTheme.accentTeal,
                      ),
                    ),
                  ],
                ),
                if (onRefresh != null)
                  IconButton(
                    iconSize: 20,
                    icon: isRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    onPressed: isRefreshing ? null : onRefresh,
                    tooltip: 'Refresh AI insight',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              insight.content,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppTheme.primaryNavy,
              ),
            ),
            if (recs.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Actionable Recommendations:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              ...recs.asMap().entries.map((entry) {
                final idx = entry.key;
                final rec = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4, right: 8),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentCyan.withValues(alpha: 0.2),
                          border: Border.all(
                            color: AppTheme.accentCyan.withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentCyan,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rec,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        '${(insight.confidence * 100).toInt()}% confidence',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Powered by Gemini 3.8 Flash',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _insightTitle(AiInsightType type) {
    switch (type) {
      case AiInsightType.earningsAdvisor:
        return 'DAILY EARNINGS ADVISOR';
      case AiInsightType.safetyCheck:
        return 'PROACTIVE SAFETY CHECK';
      case AiInsightType.maintenanceAlert:
        return 'VEHICLE HEALTH PREDICTOR';
      case AiInsightType.routeOptimization:
        return 'ROUTE OPTIMIZER';
    }
  }
}
