import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/ride_model.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ride_provider.dart';
import '../view_models/responsive_layout_helper.dart';

/// Screen displaying the user's historical trips with complete location, route,
/// fare, and timestamp metadata queried via Firestore composite indexes.
class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedFilter = 'ALL'; // 'ALL', 'COMPLETED', 'CANCELLED'

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshHistory();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);
      final rideProv = CustomChangeNotifierProvider.read<RideProvider>(context);
      final isDriver = auth.activeRole == UserRole.driver;
      if (!rideProv.isLoadingHistory && rideProv.hasMoreHistory) {
        rideProv.loadMoreHistory(
          auth.currentUser.id,
          asDriver: isDriver,
          status: _selectedFilter == 'ALL' ? null : _selectedFilter,
        );
      }
    }
  }

  Future<void> _refreshHistory() async {
    final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);
    final rideProv = CustomChangeNotifierProvider.read<RideProvider>(context);
    final isDriver = auth.activeRole == UserRole.driver;
    await rideProv.loadRideHistory(
      auth.currentUser.id,
      asDriver: isDriver,
      status: _selectedFilter == 'ALL' ? null : _selectedFilter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final isDriver = auth.activeRole == UserRole.driver;

    return Scaffold(
      backgroundColor: c.mapChrome,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.85),
                border: Border(
                  bottom: BorderSide(
                    color: c.border.withValues(alpha: isDark ? 0.3 : 0.6),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          isDriver ? 'Driver Trip History' : 'My Ride History',
          style: TextStyle(
            color: isDark ? Colors.white : AppTheme.darkNavy,
            fontWeight: FontWeight.w800,
            fontSize: layout.fontSize(18),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : AppTheme.darkNavy,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Trips',
            icon: Icon(
              Icons.refresh_rounded,
              color: AppTheme.primaryBlue,
              size: 22,
            ),
            onPressed: _refreshHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Pills Bar
            _buildFilterTabs(layout, isDark, c),

            // Rides List or Empty State
            Expanded(
              child: CustomConsumer<RideProvider>(
                builder: (context, rideProv, _) {
                  if (rideProv.isLoadingHistory && rideProv.rideHistory.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryBlue,
                      ),
                    );
                  }

                  if (rideProv.historyError != null && rideProv.rideHistory.isEmpty) {
                    return _buildErrorState(layout, rideProv.historyError!);
                  }

                  final rides = _filterRides(rideProv.rideHistory);

                  if (rides.isEmpty) {
                    return _buildEmptyState(layout, isDriver);
                  }

                  return RefreshIndicator(
                    onRefresh: _refreshHistory,
                    color: AppTheme.primaryBlue,
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        horizontal: layout.horizontalPadding,
                        vertical: layout.scale(12),
                      ),
                      itemCount: rides.length + (rideProv.hasMoreHistory ? 1 : 0),
                      separatorBuilder: (context, index) => SizedBox(height: layout.scale(12)),
                      itemBuilder: (context, index) {
                        if (index == rides.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return _buildRideCard(layout, rides[index], isDark, c);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<RideModel> _filterRides(List<RideModel> list) {
    if (_selectedFilter == 'ALL') return list;
    if (_selectedFilter == 'COMPLETED') {
      return list.where((r) => r.status == RideStatus.completed).toList();
    }
    if (_selectedFilter == 'CANCELLED') {
      return list.where((r) => r.status == RideStatus.cancelled).toList();
    }
    return list;
  }

  Widget _buildFilterTabs(
    ResponsiveLayoutHelper layout,
    bool isDark,
    AppColors c,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.horizontalPadding,
        vertical: layout.scale(8),
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          bottom: BorderSide(
            color: c.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildFilterChip('All Rides', 'ALL'),
          const SizedBox(width: 8),
          _buildFilterChip('Completed', 'COMPLETED'),
          const SizedBox(width: 8),
          _buildFilterChip('Cancelled', 'CANCELLED'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterKey) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = filterKey;
        });
        _refreshHistory();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue
              : AppTheme.primaryBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : AppTheme.primaryBlue.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.primaryBlue,
          ),
        ),
      ),
    );
  }

  Widget _buildRideCard(
    ResponsiveLayoutHelper layout,
    RideModel ride,
    bool isDark,
    AppColors c,
  ) {
    final fare = ride.acceptedFare ?? ride.offeredFare;
    final fareText = 'PKR ${fare.toStringAsFixed(0)}';
    final dateStr = _formatDate(ride.createdAt);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: c.border.withValues(alpha: isDark ? 0.3 : 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(layout.scale(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Date + Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: AppTheme.slateMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
              _buildStatusBadge(ride.status),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Route Points (Pickup & Dropoff with full location addresses)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppTheme.emeraldGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 28,
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppTheme.sunsetCoral,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.pickup.address.isNotEmpty
                          ? ride.pickup.address
                          : 'Pickup: ${ride.pickup.latitude.toStringAsFixed(4)}, ${ride.pickup.longitude.toStringAsFixed(4)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppTheme.darkNavy,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ride.dropoff.address.isNotEmpty
                          ? ride.dropoff.address
                          : 'Dropoff: ${ride.dropoff.latitude.toStringAsFixed(4)}, ${ride.dropoff.longitude.toStringAsFixed(4)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppTheme.darkNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bottom Bar: Fare, Distance, Payment Method
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.surfaceRaised.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      fareText,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.emeraldGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '0% Fee',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.emeraldGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(
                      Icons.navigation_rounded,
                      size: 13,
                      color: AppTheme.slateMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${ride.distanceKm.toStringAsFixed(1)} km',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.timer_outlined,
                      size: 13,
                      color: AppTheme.slateMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${ride.durationMin.toStringAsFixed(0)} min',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(RideStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case RideStatus.completed:
        bg = AppTheme.emeraldGreen.withValues(alpha: 0.15);
        fg = AppTheme.emeraldGreen;
        label = 'Completed';
        break;
      case RideStatus.cancelled:
        bg = AppTheme.sunsetCoral.withValues(alpha: 0.15);
        fg = AppTheme.sunsetCoral;
        label = 'Cancelled';
        break;
      case RideStatus.inProgress:
        bg = AppTheme.accentCyan.withValues(alpha: 0.15);
        fg = AppTheme.accentCyan;
        label = 'In Progress';
        break;
      case RideStatus.accepted:
      case RideStatus.driverArrived:
        bg = AppTheme.primaryBlue.withValues(alpha: 0.15);
        fg = AppTheme.primaryBlue;
        label = 'Driver En Route';
        break;
      case RideStatus.requested:
        bg = AppTheme.amberWarning.withValues(alpha: 0.15);
        fg = AppTheme.amberWarning;
        label = 'Searching';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ResponsiveLayoutHelper layout, bool isDriver) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.scale(24)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car_filled_rounded,
                size: 54,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isDriver ? 'No Trips Completed Yet' : 'No Ride History Found',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.darkNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isDriver
                  ? 'Your completed rides and earnings will show up here.'
                  : 'Start booking zero-commission rides to build your trip history.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.map_rounded, size: 18),
              label: Text(isDriver ? 'Go Online' : 'Book a Ride Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ResponsiveLayoutHelper layout, String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.scale(24)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppTheme.sunsetCoral,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refreshHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) {
      return 'Today at $timeStr';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $timeStr';
  }
}
