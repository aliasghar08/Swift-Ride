import 'package:flutter/material.dart';
import '../../../core/provider/custom_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../providers/driver_provider.dart';
import '../../presentation/../../presentation/common/glass_container.dart';
import '../../presentation/../../presentation/common/staggered_animation.dart';
import '../providers/earnings_advisor_provider.dart';
import '../widgets/ai_insight_card.dart';

class EarningsAdvisorScreen extends StatefulWidget {
  const EarningsAdvisorScreen({super.key});

  @override
  State<EarningsAdvisorScreen> createState() => _EarningsAdvisorScreenState();
}

class _EarningsAdvisorScreenState extends State<EarningsAdvisorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final driverProv = CustomChangeNotifierProvider.read<DriverProvider>(context);
      final earningsProv = CustomChangeNotifierProvider.read<EarningsAdvisorProvider>(context);
      earningsProv.loadEarningsInsight(driverProv.driver.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);

    return CustomConsumer<EarningsAdvisorProvider>(
      builder: (context, advisorProv, _) {
        final insight = advisorProv.insight;
        final isLoading = advisorProv.isLoading;

        return Scaffold(
          appBar: AppBar(
            title: const Text('AI Earnings Advisor'),
            actions: [
              IconButton(
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Regenerate Forecast',
                onPressed: isLoading ? null : () => advisorProv.refresh(driverProv.driver.id),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Zero Commission Banner
                StaggeredEntryWidget(
                  index: 0,
                  child: GlassContainer(
                    isDark: isDark,
                    borderRadius: 18,
                    padding: const EdgeInsets.all(16),
                    borderColor: AppTheme.accentTeal.withValues(alpha: 0.4),
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              AppTheme.accentTeal.withValues(alpha: 0.15),
                              AppTheme.primaryNavy.withValues(alpha: 0.25),
                            ]
                          : [
                              AppTheme.accentTeal.withValues(alpha: 0.1),
                              Colors.white.withValues(alpha: 0.9),
                            ],
                    ),
                    child: Row(
                      children: [
                        PulsingGlowWidget(
                          glowColor: AppTheme.accentTeal,
                          minSpread: 2.0,
                          maxSpread: 5.0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.accentTeal,
                            ),
                            child: const Icon(Icons.paid, size: 20, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Year 1 Zero Commission Active',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accentTeal,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'You keep 100% of all gross passenger fares (${CurrencyFormatter.format(driverProv.driver.totalEarnings)} earned).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // AI Insight Card
                if (insight != null)
                  AiInsightCard(
                    insight: insight,
                    isRefreshing: isLoading,
                    onRefresh: () => advisorProv.refresh(driverProv.driver.id),
                  )
                else if (isLoading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Analyzing trips and demand with Gemini 3.8 Flash...',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // Heatmap & Surge Zones
                StaggeredEntryWidget(
                  index: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Projected Surge Hotspots Today',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _buildHotspotTile(
                        isDark: isDark,
                        name: 'Downtown Financial Center',
                        peak: '07:30 - 09:30 AM & 16:30 - 19:00',
                        multiplier: '1.4x Surge',
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      _buildHotspotTile(
                        isDark: isDark,
                        name: 'City Sports Arena (Evening Match)',
                        peak: '19:15 - 22:30 PM',
                        multiplier: '1.5x Surge',
                        color: Colors.redAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildHotspotTile(
                        isDark: isDark,
                        name: 'International Airport Corridor',
                        peak: 'All Day Steady Demand',
                        multiplier: '1.2x Steady',
                        color: Colors.blueAccent,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Vehicle Maintenance Alert preview
                StaggeredEntryWidget(
                  index: 2,
                  child: GlassContainer(
                    isDark: isDark,
                    borderRadius: 18,
                    padding: const EdgeInsets.all(16),
                    borderColor: Colors.blue.withValues(alpha: 0.3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue.withValues(alpha: 0.2),
                          ),
                          child: const Icon(Icons.build_circle, size: 22, color: Colors.blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Predictive Vehicle Health',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Vehicle fleet usage is optimal. Next recommended tire rotation and brake fluid check in 1,200 km.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHotspotTile({
    required bool isDark,
    required String name,
    required String peak,
    required String multiplier,
    required Color color,
  }) {
    return GlassContainer(
      isDark: isDark,
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: color.withValues(alpha: 0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  peak,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              multiplier,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
