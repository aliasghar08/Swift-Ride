import 'package:flutter/material.dart';
import '../../../core/provider/custom_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../domain/models/vehicle_info_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_khata_service.dart';
import 'driver_khata_sheet.dart';
import 'driver_name_dialog.dart';

/// Full-featured, production-grade Driver Analytics Navigation Drawer.
/// Displays driver identity, daily cash ledger (Khata), 2% fee economics,
/// operational performance stats, and rapid navigation shortcuts.
class DriverAnalyticsDrawer extends StatelessWidget {
  const DriverAnalyticsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    final user = auth.currentUser;
    final driver = driverProv.driverProfile;

    // Platform economics
    final totalGross = driver.totalEarnings;
    final platformFee = totalGross * 0.02;
    final driverTakeHome = totalGross * 0.98;

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: SafeArea(
        child: Column(
          children: [
            // 1. Header: Driver Identity & Edit Name
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        child: Text(
                          user.fullName.isNotEmpty
                              ? user.fullName.trim()[0].toUpperCase()
                              : 'D',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.emeraldGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    user.fullName.isNotEmpty ? user.fullName : 'Driver',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : AppTheme.darkNavy,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  color: AppTheme.emeraldGreen,
                                  tooltip: 'Edit Driver Name',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: () {
                                    DriverNameDialog.show(
                                      context,
                                      currentName: user.fullName,
                                      barrierDismissible: true,
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.phone.isNotEmpty ? user.phone : 'Unregistered phone',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : AppTheme.slateMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star, size: 12, color: AppTheme.amberWarning),
                                      const SizedBox(width: 3),
                                      Text(
                                        driver.rating.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.emeraldGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (driver.isVerified ? AppTheme.accentCyan : Colors.orange)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        driver.isVerified ? Icons.verified : Icons.pending,
                                        size: 12,
                                        color: driver.isVerified ? AppTheme.accentCyan : Colors.orange,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        driver.isVerified ? 'Verified' : 'Pending',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: driver.isVerified ? AppTheme.accentCyan : Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (driver.vehicle.plate.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            driver.vehicle.carTier == 0
                                ? Icons.two_wheeler
                                : (driver.vehicle.carTier == 1
                                    ? Icons.electric_rickshaw
                                    : Icons.directions_car_filled),
                            size: 15,
                            color: AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${driver.vehicle.make} ${driver.vehicle.model} • ${driver.vehicle.plate}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : AppTheme.darkNavy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 2. Scrollable Analytics Body
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                children: [
                  // --- Daily Khata Snapshot ---
                  _buildSectionHeader(
                    context,
                    title: "Today's Cash Ledger (Khata)",
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 10),
                  ListenableBuilder(
                    listenable: DriverKhataService(),
                    builder: (context, _) {
                      final khata = DriverKhataService().todayKhata;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricTile(
                                    label: 'Cash in Pocket',
                                    value: 'PKR ${khata.totalGrossCashCollected.toInt()}',
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildMetricTile(
                                    label: 'Fuel Expense',
                                    value: '-PKR ${khata.totalFuelExpense.toInt()}',
                                    valueColor: AppTheme.sunsetCoral,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricTile(
                                    label: 'Maintenance',
                                    value: '-PKR ${khata.totalMaintenanceReserve.toInt()}',
                                    valueColor: AppTheme.amberWarning,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildMetricTile(
                                    label: 'Net Take-Home',
                                    value: 'PKR ${khata.netCashProfit.toInt()}',
                                    valueColor: AppTheme.emeraldGreen,
                                    isBold: true,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  DriverKhataSheet.show(context);
                                },
                                icon: const Icon(Icons.receipt_long, size: 15),
                                label: const Text('Manage Daily Khata'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.emeraldGreen,
                                  side: const BorderSide(color: AppTheme.emeraldGreen),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  // --- 2% Commission Economics ---
                  _buildSectionHeader(
                    context,
                    title: 'Earnings & 2% Commission',
                    icon: Icons.trending_up_rounded,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Gross Fares',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : AppTheme.slateMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(totalGross),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : AppTheme.darkNavy,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Driver Share (98%)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white70 : AppTheme.slateMuted,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, size: 13, color: AppTheme.emeraldGreen),
                                ],
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(driverTakeHome),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.emeraldGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Platform Fee (2%)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : AppTheme.slateMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(platformFee),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white54 : AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 14, color: AppTheme.emeraldGreen),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Permanent Policy: Fixed 2% fee always gives you 98% take-home on every trip.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.emeraldGreen,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // --- Trip Performance Metrics ---
                  _buildSectionHeader(
                    context,
                    title: 'Driver Performance',
                    icon: Icons.speed_rounded,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Total Rides',
                          value: '${driver.totalRides}',
                          subtitle: 'Completed',
                          icon: Icons.local_taxi_rounded,
                          color: AppTheme.primaryBlue,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Acceptance',
                          value: '98.5%',
                          subtitle: 'Past 30 days',
                          icon: Icons.thumb_up_alt_rounded,
                          color: AppTheme.emeraldGreen,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Completion',
                          value: '99.1%',
                          subtitle: 'Zero cancels',
                          icon: Icons.check_circle_outline_rounded,
                          color: AppTheme.accentCyan,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Rating',
                          value: '${driver.rating.toStringAsFixed(1)} ★',
                          subtitle: 'Top tier',
                          icon: Icons.star_rounded,
                          color: AppTheme.amberWarning,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // --- Navigation Shortcuts ---
                  _buildSectionHeader(
                    context,
                    title: 'Quick Actions',
                    icon: Icons.explore_outlined,
                  ),
                  const SizedBox(height: 10),
                  _buildDrawerActionTile(
                    title: 'AI Earnings Advisor',
                    subtitle: 'Predictive surge hotspots & timing',
                    icon: Icons.psychology,
                    iconColor: AppTheme.accentTeal,
                    isDark: isDark,
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed('/earnings-advisor');
                    },
                  ),
                  _buildDrawerActionTile(
                    title: 'Trip History',
                    subtitle: 'Completed rides & passenger receipts',
                    icon: Icons.history,
                    iconColor: AppTheme.primaryBlue,
                    isDark: isDark,
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed('/history');
                    },
                  ),
                  _buildDrawerActionTile(
                    title: 'Driver Identity & Name',
                    subtitle: 'Update legal name for receipts',
                    icon: Icons.badge_outlined,
                    iconColor: AppTheme.emeraldGreen,
                    isDark: isDark,
                    onTap: () {
                      DriverNameDialog.show(
                        context,
                        currentName: user.fullName,
                        barrierDismissible: true,
                      );
                    },
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'SwiftRide Driver v1.0.7',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : AppTheme.slateMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Close', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : AppTheme.darkNavy,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 15, color: AppTheme.emeraldGreen),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : AppTheme.darkNavy,
              letterSpacing: 0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white60 : AppTheme.slateMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor ?? (isDark ? Colors.white : AppTheme.darkNavy),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : AppTheme.slateMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 15, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppTheme.darkNavy,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : AppTheme.slateMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          onTap: onTap,
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.darkNavy,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : AppTheme.slateMuted,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            size: 16,
            color: isDark ? Colors.white38 : AppTheme.slateMuted,
          ),
        ),
      ),
    );
  }
}
