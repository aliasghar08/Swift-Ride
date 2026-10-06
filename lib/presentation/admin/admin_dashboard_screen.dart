import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_status.dart';
import '../../providers/admin_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/ride_provider.dart';
import '../common/confirm_action.dart';
import '../common/glass_container.dart';
import '../common/skeleton.dart';
import '../common/staggered_animation.dart';
import '../view_models/admin_view_model.dart';
import '../view_models/responsive_layout_helper.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminViewModel _viewModel;
  bool _adminDataRequested = false;

  @override
  void initState() {
    super.initState();
    _viewModel = AdminViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_adminDataRequested) return;
    _adminDataRequested = true;

    // Pull real platform metrics and the live verification queue. The dashboard
    // previously showed only locally-computed figures from this session.
    //
    // Deferred to after the frame: loadStats() notifies listeners immediately
    // (to show its loading state), which is illegal during the build phase.
    final adminProv = CustomChangeNotifierProvider.of<AdminProvider>(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      adminProv.watchPendingDrivers();
      adminProv.loadStats();
      adminProv.loadPlatformRides();
      // The ride log previously showed only rides completed in this session.
    });
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final c = AppColors.of(context);
    final adminProv = CustomChangeNotifierProvider.of<AdminProvider>(context);
    final rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);

    final kpis = adminProv.getKpis(
      rideHistory: rideProv.rideHistory,
      currentRide: rideProv.currentRide,
      allDrivers: [driverProv.driverProfile],
    );

    final filteredDrivers = _viewModel.filterDrivers(adminProv.pendingDrivers);

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: c.canvas,
          body: SingleChildScrollView(
            padding: EdgeInsets.all(layout.horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Admin Header
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SwiftRide Operations & Admin Dashboard',
                      style: TextStyle(
                        fontSize: layout.fontSize(18),
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Zero Commission Platform Monitoring • Regional Fleet Operations',
                      style: TextStyle(fontSize: layout.fontSize(11), color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: AppTheme.emeraldGreen, size: 14),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Year 1: 0% Platform Commission',
                              style: TextStyle(
                                color: AppTheme.emeraldGreen,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: layout.scale(16)),

                // Metrics loading / failure surface. Previously the grid
                // rendered zeros with no indication that data had failed to load.
                if (adminProv.isLoadingStats && !adminProv.hasServerStats)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: SkeletonCard(lines: 2),
                  )
                else if (adminProv.statsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassContainer(
                      borderRadius: 14,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off, color: c.danger, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              adminProv.statsError!,
                              style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                            ),
                          ),
                          TextButton(
                            onPressed: adminProv.loadStats,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Top KPI Cards Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    final isCompact = constraints.maxWidth < 360;
                    final cardWidth = isWide
                        ? (constraints.maxWidth - 36) / 4
                        : (isCompact ? constraints.maxWidth : (constraints.maxWidth - 12) / 2);

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildKpiCard(
                          layout: layout,
                          title: 'Gross Booking Volume',
                          value: CurrencyFormatter.format(kpis.grossMarketplaceValue),
                          subtitle: '${kpis.totalRides} rides booked',
                          icon: Icons.payments,
                          iconColor: AppTheme.primaryBlue,
                          width: cardWidth,
                        ),
                        _buildKpiCard(
                          layout: layout,
                          title: 'Driver Savings (100%)',
                          value: CurrencyFormatter.format(kpis.driverCommissionSavings),
                          subtitle: 'Saved vs 13% commission',
                          icon: Icons.savings,
                          iconColor: AppTheme.emeraldGreen,
                          width: cardWidth,
                        ),
                        _buildKpiCard(
                          layout: layout,
                          // Now a genuine platform aggregate from
                          // getDashboardStats (it previously reported this
                          // device's own session as if it were the fleet).
                          title: 'Active Fleet Online',
                          value: '${kpis.activeDrivers}',
                          subtitle: adminProv.hasServerStats
                              ? 'Verified drivers online now'
                              : 'Connect to load live fleet',
                          icon: Icons.directions_car,
                          iconColor: AppTheme.accentCyan,
                          width: cardWidth,
                        ),
                        _buildKpiCard(
                          layout: layout,
                          title: 'Safety Alerts (SOS)',
                          // A platform-wide figure from getDashboardStats. This
                          // read a local list that only ever held alerts raised
                          // on this admin's own device, so it showed 0 while a
                          // rider could be in an active emergency.
                          value: kpis.unresolvedSafetyEvents == null
                              ? '—'
                              : '${kpis.unresolvedSafetyEvents}',
                          subtitle: kpis.unresolvedSafetyEvents == null
                              ? 'Connect to load alerts'
                              : (kpis.unresolvedSafetyEvents == 0
                                  ? 'No open alerts'
                                  : 'Open alerts — act now'),
                          icon: Icons.warning_amber_rounded,
                          iconColor: (kpis.unresolvedSafetyEvents ?? 0) > 0
                              ? AppTheme.sunsetCoral
                              : Colors.grey,
                          width: cardWidth,
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: layout.scale(20)),

                // Driver Verification Portal Section
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: EdgeInsets.all(layout.scale(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.badge, color: AppTheme.primaryBlue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Driver Verification Queue',
                                      style: TextStyle(fontSize: layout.fontSize(15), fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${filteredDrivers.length} Pending',
                              style: TextStyle(color: AppTheme.slateMuted, fontWeight: FontWeight.w600, fontSize: layout.fontSize(13)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Search filter box
                        TextField(
                          onChanged: (q) => _viewModel.setSearchQuery(q),
                          decoration: InputDecoration(
                            hintText: 'Search by driver ID, license, or plate...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: c.border),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (filteredDrivers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            alignment: Alignment.center,
                            child: const Text('All submitted driver documents are verified and up to date!'),
                          )
                        else
                          ...filteredDrivers.asMap().entries.map(
                                (entry) => _buildDriverQueueItem(layout, entry.value, adminProv, entry.key),
                              ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: layout.scale(20)),

                // Live Ride Activity Section
                GlassContainer(
                  borderRadius: 20,
                  blur: 16,
                  padding: EdgeInsets.all(layout.scale(16)),
                  shadows: AppTheme.subtleElevation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.receipt_long, color: AppTheme.primaryBlue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Live Ride Activity & Completed Trips Log',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (adminProv.platformRides.isEmpty &&
                          !adminProv.isLoadingRides &&
                          adminProv.ridesError != null)
                        Container(
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Icon(Icons.cloud_off, color: c.danger, size: 22),
                              const SizedBox(height: 8),
                              Text(
                                adminProv.ridesError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12.5, color: c.textMuted),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () => adminProv.loadPlatformRides(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      else if (adminProv.platformRides.isEmpty && !adminProv.isLoadingRides)
                        Container(
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.center,
                          child: Text(
                            'No rides on the platform yet.',
                            style: TextStyle(fontSize: 12.5, color: c.textMuted),
                          ),
                        )
                      else ...[
                        ...adminProv.platformRides.asMap().entries.map(
                              (e) => _buildRideLogTile(
                                layout,
                                e.value,
                                // Still in flight, as reported by the server.
                                isActive: e.value.status != RideStatus.completed &&
                                    e.value.status != RideStatus.cancelled,
                                index: e.key,
                              ),
                            ),
                        if (adminProv.isLoadingRides)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: SkeletonCard(lines: 1),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton(
                              onPressed: () => adminProv.loadPlatformRides(),
                              child: const Text('Refresh'),
                            ),
                          ),
                    ],
                      ],
                    ),
                  ),
            ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required ResponsiveLayoutHelper layout,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required double width,
    int index = 0,
  }) {
    final c = AppColors.of(layout.context);
    return StaggeredEntryWidget(
      index: index,
      child: GlassContainer(
        width: width,
        borderRadius: 16,
        blur: 16,
        padding: EdgeInsets.all(layout.scale(12)),
        shadows: AppTheme.glowShadow(iconColor, opacity: 0.08, blur: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(color: AppTheme.slateMuted, fontSize: layout.fontSize(11), fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.glowShadow(iconColor, opacity: 0.2, blur: 8),
                  ),
                  child: Icon(icon, color: iconColor, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: layout.fontSize(18), fontWeight: FontWeight.w800, color: c.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: layout.fontSize(10), color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverQueueItem(
    ResponsiveLayoutHelper layout,
    DriverProfile driver,
    AdminProvider adminProv,
    int index,
  ) {
    final c = AppColors.of(layout.context);
    return StaggeredEntryWidget(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(layout.scale(12)),
        decoration: BoxDecoration(
          color: c.canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border),
          boxShadow: AppTheme.subtleElevation,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  child: const Icon(Icons.person, color: AppTheme.primaryBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver.userId, style: TextStyle(fontWeight: FontWeight.w700, fontSize: layout.fontSize(13))),
                      Text(
                        '${driver.vehicle.color} ${driver.vehicle.make} ${driver.vehicle.model} (${driver.vehicle.plate})',
                        style: TextStyle(fontSize: layout.fontSize(11), color: AppTheme.slateMuted),
                      ),
                      Text(
                        'License: ${driver.licenseNumber} • Background Check: Submitted',
                        style: TextStyle(fontSize: layout.fontSize(10), color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  height: layout.touchTarget(38),
                  child: OutlinedButton(
                    // Rejecting an application is irreversible from this
                    // screen, so it is confirmed rather than fired on one tap.
                    onPressed: () async {
                      final confirmed = await confirmAction(
                        layout.context,
                        title: 'Reject this application?',
                        message:
                            'This applicant will not be able to accept trips on SwiftRide.',
                        confirmLabel: 'Reject',
                        cancelLabel: 'Back',
                        destructive: true,
                        icon: Icons.gpp_bad_outlined,
                      );
                      if (!confirmed) return;

                      final ok = await _viewModel.processDriverVerification(
                        adminProv: adminProv,
                        driverId: driver.userId,
                        approve: false,
                      );
                      if (!layout.context.mounted) return;
                      ScaffoldMessenger.of(layout.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Application rejected.'
                                : 'We could not reject that application. Please try again.',
                          ),
                          backgroundColor: ok ? AppTheme.slateMuted : AppTheme.sunsetCoral,
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.sunsetCoral,
                      side: BorderSide(color: c.danger.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text('Reject Application', style: TextStyle(fontSize: 12)),
                  ),
                ),
                SizedBox(
                  height: layout.touchTarget(38),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emeraldGreen,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () async {
                      final ok = await _viewModel.processDriverVerification(
                        adminProv: adminProv,
                        driverId: driver.userId,
                        approve: true,
                      );
                      if (!layout.context.mounted) return;
                      ScaffoldMessenger.of(layout.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Driver approved.'
                                : 'We could not approve that driver. Please try again.',
                          ),
                          backgroundColor: ok ? AppTheme.emeraldGreen : AppTheme.sunsetCoral,
                        ),
                      );
                    },
                    child: const Text('Approve License', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideLogTile(
    ResponsiveLayoutHelper layout,
    RideModel ride, {
    required bool isActive,
    int index = 0,
  }) {
    final c = AppColors.of(layout.context);
    return StaggeredEntryWidget(
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(layout.scale(12)),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryBlue.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? AppTheme.primaryBlue.withValues(alpha: 0.3) : c.border),
          boxShadow: isActive ? AppTheme.glowShadow(AppTheme.primaryBlue, opacity: 0.1, blur: 8) : AppTheme.subtleElevation,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.play_circle_filled : Icons.check_circle,
              color: isActive ? AppTheme.primaryBlue : AppTheme.emeraldGreen,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Ride #${ride.id.toUpperCase()}',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: layout.fontSize(12)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.primaryBlue.withValues(alpha: 0.12) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isActive ? 'IN PROGRESS (PIN: ${ride.pin})' : 'COMPLETED',
                          style: TextStyle(
                            fontSize: layout.fontSize(9),
                            fontWeight: FontWeight.bold,
                            color: isActive ? AppTheme.primaryBlue : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${ride.pickup.address} → ${ride.dropoff.address}',
                    style: TextStyle(fontSize: layout.fontSize(11), color: AppTheme.slateMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              CurrencyFormatter.format(ride.acceptedFare ?? ride.offeredFare),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: layout.fontSize(14), color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
