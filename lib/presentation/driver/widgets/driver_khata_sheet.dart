import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../services/driver_khata_service.dart';
import '../../view_models/responsive_layout_helper.dart';

/// Modal bottom sheet displaying the Driver's Daily Financial Ledger ("Khata").
/// Reconciles physical cash in pocket, live fuel burned, and vehicle wear reserve.
class DriverKhataSheet extends StatelessWidget {
  final DriverKhataService khataService;

  const DriverKhataSheet({
    super.key,
    required this.khataService,
  });

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DriverKhataSheet(
        khataService: DriverKhataService(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);

    return ListenableBuilder(
      listenable: khataService,
      builder: (context, _) {
        final khata = khataService.todayKhata;
        final netProfit = khata.netCashProfit;

        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            layout.scale(20),
            layout.scale(12),
            layout.scale(20),
            layout.scale(28) + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: c.border.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: AppTheme.emeraldGreen,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Driver Daily Khata (کھاتہ)",
                            style: TextStyle(
                              fontSize: layout.fontSize(16),
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : c.textPrimary,
                            ),
                          ),
                          Text(
                            "${khata.completedTrips} Trips Completed Today",
                            style: TextStyle(
                              fontSize: layout.fontSize(12),
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Top Emerald Card: Aaj Ki Bachat (Net Profit)
              Container(
                padding: EdgeInsets.all(layout.scale(18)),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppTheme.emeraldGreen,
                      Color(0xFF00796B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      "Aaj Ki Bachat (Net Take-Home Cash)",
                      style: TextStyle(
                        fontSize: layout.fontSize(13),
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      CurrencyFormatter.format(netProfit.roundToDouble()),
                      style: TextStyle(
                        fontSize: layout.fontSize(32),
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            "SwiftRide Fee: PKR 0 (100% Cash Retained)",
                            style: TextStyle(
                              fontSize: layout.fontSize(11),
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Breakdown Summary Cards
              Row(
                children: [
                  // Gross Cash Collected
                  Expanded(
                    child: _buildMetricTile(
                      layout: layout,
                      isDark: isDark,
                      c: c,
                      icon: Icons.payments_rounded,
                      iconColor: AppTheme.emeraldGreen,
                      title: "Cash Collected",
                      amount: CurrencyFormatter.format(khata.totalGrossCashCollected),
                      subtitle: "In Pocket",
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Fuel Burn Expense
                  Expanded(
                    child: _buildMetricTile(
                      layout: layout,
                      isDark: isDark,
                      c: c,
                      icon: Icons.local_gas_station_rounded,
                      iconColor: AppTheme.sunsetCoral,
                      title: "Fuel Burned",
                      amount: "-${CurrencyFormatter.format(khata.totalFuelExpense)}",
                      subtitle: "Live OGRA Rate",
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Wear Reserve
                  Expanded(
                    child: _buildMetricTile(
                      layout: layout,
                      isDark: isDark,
                      c: c,
                      icon: Icons.build_circle_rounded,
                      iconColor: AppTheme.amberWarning,
                      title: "Wear Reserve",
                      amount: "-${CurrencyFormatter.format(khata.totalMaintenanceReserve)}",
                      subtitle: "Vehicle Wear",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Audit Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppTheme.accentCyan,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Khata auto-deducts live fuel costs and mechanical tire/oil wear so you know your exact real profit for today.",
                        style: TextStyle(
                          fontSize: layout.fontSize(11),
                          color: c.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Close / Done Button
              SizedBox(
                height: layout.touchTarget(48),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to Driving (واپس جائیں)'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required ResponsiveLayoutHelper layout,
    required bool isDark,
    required dynamic c,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String amount,
    required String subtitle,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.scale(8),
        vertical: layout.scale(12),
      ),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: layout.fontSize(10),
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: layout.fontSize(12),
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : c.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: layout.fontSize(9),
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
