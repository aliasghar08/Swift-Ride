import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/trip_economics_model.dart';
import '../../domain/models/vehicle_type.dart';
import '../../services/fuel_price_service.dart';
import '../../services/pricing_ml_service.dart';
import '../view_models/responsive_layout_helper.dart';

/// Modal bottom sheet and inline card displaying real-time trip economics:
/// - Live fuel rates fetched from the internet (OGRA Pakistan) with manual/auto sync
/// - Seating capacity and seat reservation (1 for bike, 2 for rikshaw, 4 for car)
/// - Fuel consumption and fuel cost calculated with vehicle mileage & petrol rates
/// - Wear-and-tear vehicle maintenance charges
/// - 0% platform service charges
/// - Step-by-step transparent mathematical formulas and calculation breakdown
/// - Net driver take-home profit & earning rate per minute
class TripEconomicsSheet extends StatefulWidget {
  final TripEconomics economics;
  final bool isDriverView;
  final ValueChanged<int>? onSeatCountChanged;

  const TripEconomicsSheet({
    super.key,
    required this.economics,
    this.isDriverView = false,
    this.onSeatCountChanged,
  });

  static void show(
    BuildContext context, {
    required TripEconomics economics,
    bool isDriverView = false,
    ValueChanged<int>? onSeatCountChanged,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TripEconomicsSheet(
        economics: economics,
        isDriverView: isDriverView,
        onSeatCountChanged: onSeatCountChanged,
      ),
    );
  }

  @override
  State<TripEconomicsSheet> createState() => _TripEconomicsSheetState();
}

class _TripEconomicsSheetState extends State<TripEconomicsSheet> {
  late TripEconomics _econ;
  bool _isRefreshingFuel = false;
  bool _showFormulas = true;

  @override
  void initState() {
    super.initState();
    _econ = widget.economics;
    // Check for fresh internet fuel rates on open and auto-update
    FuelPriceService().fetchLivePrices().then((live) async {
      if (mounted &&
          (live.petrolPricePerL != _econ.fuelPricePerL ||
              live.isLive != _econ.isFuelPriceLive)) {
        final updated = await _recalculateEconomics(
          fuelPrice: live.petrolPricePerL,
          source: live.source,
          isLive: live.isLive,
        );
        if (mounted) setState(() => _econ = updated);
      }
    });
  }

  Future<TripEconomics> _recalculateEconomics({
    required double fuelPrice,
    required String source,
    required bool isLive,
    int? overrideSeats,
  }) async {
    final seats = overrideSeats ?? _econ.bookedSeats;
    if (_econ.isAiPredicted) {
      return await PricingMLService().predictTripEconomics(
        distanceKm: _econ.distanceKm,
        durationMin: _econ.durationMin.round(),
        vehicleType: _econ.vehicleType,
        bookedSeats: seats,
        fuelPrice: fuelPrice,
      );
    } else {
      return TripEconomics.calculate(
        distanceKm: _econ.distanceKm,
        durationMin: _econ.durationMin,
        fare: _econ.totalFare,
        vehicleType: _econ.vehicleType,
        bookedSeats: seats,
        fuelPricePerL: fuelPrice,
        fuelPriceSource: source,
        isFuelPriceLive: isLive,
        isAiPredicted: _econ.isAiPredicted,
      );
    }
  }

  Future<void> _refreshLiveFuel() async {
    setState(() => _isRefreshingFuel = true);
    final live = await FuelPriceService().fetchLivePrices(force: true);
    if (!mounted) return;
    final updated = await _recalculateEconomics(
      fuelPrice: live.petrolPricePerL,
      source: live.source,
      isLive: live.isLive,
    );
    if (!mounted) return;
    setState(() {
      _isRefreshingFuel = false;
      _econ = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Live Rates Updated: PKR ${live.petrolPricePerL.toStringAsFixed(1)}/L (${live.source})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppTheme.emeraldGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vType = _econ.vehicleType;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131927) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        layout.scale(20),
        layout.scale(12),
        layout.scale(20),
        MediaQuery.of(context).padding.bottom + layout.scale(20),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: layout.scale(42),
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header: Vehicle Title & 0% Commission Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    vType.icon,
                    color: AppTheme.primaryBlue,
                    size: layout.scale(24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${vType.title} • Trip Economics',
                        style: TextStyle(
                          fontSize: layout.fontSize(16),
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_econ.distanceKm.toStringAsFixed(1)} km • ${_econ.durationMin.round()} mins',
                        style: TextStyle(
                          fontSize: layout.fontSize(12),
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.emeraldGreen.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: AppTheme.emeraldGreen,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '0% Commission',
                            style: TextStyle(
                              fontSize: layout.fontSize(11),
                              fontWeight: FontWeight.w800,
                              color: AppTheme.emeraldGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_econ.isAiPredicted) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.emeraldGreen.withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: AppTheme.emeraldGreen,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'AI Predictive Model',
                              style: TextStyle(
                                fontSize: layout.fontSize(10.5),
                                fontWeight: FontWeight.w800,
                                color: AppTheme.emeraldGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Live Fuel Internet Rates Banner with Sync Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _econ.isFuelPriceLive
                    ? AppTheme.emeraldGreen.withValues(alpha: 0.10)
                    : Colors.amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _econ.isFuelPriceLive
                      ? AppTheme.emeraldGreen.withValues(alpha: 0.35)
                      : Colors.amber.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _econ.isFuelPriceLive ? Icons.sensors_rounded : Icons.cloud_done_rounded,
                    color: _econ.isFuelPriceLive ? AppTheme.emeraldGreen : Colors.amber.shade800,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'LIVE PETROL PRICE: ',
                              style: TextStyle(
                                fontSize: layout.fontSize(10),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: _econ.isFuelPriceLive
                                    ? AppTheme.emeraldGreen
                                    : Colors.amber.shade900,
                              ),
                            ),
                            Text(
                              'PKR ${_econ.fuelPricePerL.toStringAsFixed(1)} / Liter',
                              style: TextStyle(
                                fontSize: layout.fontSize(11),
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : c.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Source: ${_econ.fuelPriceSource}',
                          style: TextStyle(
                            fontSize: layout.fontSize(9.5),
                            color: AppTheme.slateMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _isRefreshingFuel ? null : _refreshLiveFuel,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _isRefreshingFuel
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: AppTheme.accentCyan,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Seating Reservation Selector / Indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.airline_seat_recline_normal_rounded,
                            size: 18,
                            color: AppTheme.accentCyan,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Seating Reservation',
                            style: TextStyle(
                              fontSize: layout.fontSize(13),
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${_econ.bookedSeats} of ${vType.seats} ${_econ.bookedSeats == 1 ? 'Seat' : 'Seats'}',
                        style: TextStyle(
                          fontSize: layout.fontSize(12.5),
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vType == VehicleType.bike
                        ? '1 Passenger Seat (Solo Rider • Fastest in traffic)'
                        : vType == VehicleType.rikshaw
                            ? 'Up to 2 Passenger Seats (Economical Local Ride)'
                            : 'Up to 4 Passenger Seats (Air Conditioned Comfort)',
                    style: TextStyle(
                      fontSize: layout.fontSize(11),
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  if (widget.onSeatCountChanged != null && vType.seats > 1) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(vType.seats, (idx) {
                        final seatNum = idx + 1;
                        final isSelected = seatNum == _econ.bookedSeats;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: idx < vType.seats - 1 ? 6 : 0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                widget.onSeatCountChanged?.call(seatNum);
                                final updated = await _recalculateEconomics(
                                  fuelPrice: _econ.fuelPricePerL,
                                  source: _econ.fuelPriceSource,
                                  isLive: _econ.isFuelPriceLive,
                                  overrideSeats: seatNum,
                                );
                                if (mounted) setState(() => _econ = updated);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryBlue
                                      : isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? AppTheme.primaryBlue : c.border,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 16,
                                      color: isSelected ? Colors.white : AppTheme.slateMuted,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      seatNum == vType.seats && vType.seats > 2
                                          ? '$seatNum (Full)'
                                          : '$seatNum ${seatNum == 1 ? 'Seat' : 'Seats'}',
                                      style: TextStyle(
                                        fontSize: layout.fontSize(10.5),
                                        fontWeight: FontWeight.w700,
                                        color: isSelected ? Colors.white : c.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Economics Breakdown Items
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2335) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  _buildRow(
                    layout: layout,
                    c: c,
                    icon: Icons.local_gas_station_rounded,
                    iconColor: Colors.amber.shade700,
                    title: _econ.isPredictedFromGoogleMaps
                        ? 'Fuel (Google Maps Traffic Calibrated)'
                        : 'Fuel Consumption',
                    subtitle: _econ.trafficConditionNote != null
                        ? '${_econ.distanceKm.toStringAsFixed(1)}km @ ${_econ.vehicleMileageKmPerL.toStringAsFixed(1)} km/L · ${_econ.trafficConditionNote}'
                        : '${_econ.distanceKm.toStringAsFixed(1)}km @ ${_econ.vehicleMileageKmPerL.toStringAsFixed(0)} km/L (Rs ${_econ.fuelPricePerL.toInt()}/L)',
                    trailing: '- PKR ${_econ.fuelCost.toStringAsFixed(0)}',
                    trailingColor: Colors.orange.shade700,
                  ),
                  Divider(height: 18, color: c.border.withValues(alpha: 0.6)),
                  _buildRow(
                    layout: layout,
                    c: c,
                    icon: Icons.build_circle_rounded,
                    iconColor: Colors.blueGrey,
                    title: 'Maintenance & Wear',
                    subtitle:
                        'Oil, tires, brakes @ Rs ${_econ.maintenanceRatePerKm.toStringAsFixed(1)}/km',
                    trailing: '- PKR ${_econ.maintenanceCost.toStringAsFixed(0)}',
                    trailingColor: Colors.blueGrey,
                  ),
                  Divider(height: 18, color: c.border.withValues(alpha: 0.6)),
                  _buildRow(
                    layout: layout,
                    c: c,
                    icon: Icons.shield_rounded,
                    iconColor: AppTheme.emeraldGreen,
                    title: 'Platform Service Fee',
                    subtitle: 'SwiftRide 0% commission direct direct-to-driver',
                    trailing: 'PKR 0.00',
                    trailingColor: AppTheme.emeraldGreen,
                  ),
                  Divider(height: 18, color: c.border.withValues(alpha: 0.6)),
                  _buildRow(
                    layout: layout,
                    c: c,
                    icon: Icons.receipt_long_rounded,
                    iconColor: AppTheme.primaryBlue,
                    title: 'Total Rider Fare',
                    subtitle: widget.isDriverView
                        ? 'Gross amount paid by passenger'
                        : 'Agreed trip payment',
                    trailing: 'PKR ${_econ.totalFare.toStringAsFixed(0)}',
                    trailingColor: c.textPrimary,
                    isBold: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Step-by-Step Transparent Mathematical Formulas & Proof Card
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161F30) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.accentCyan.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _showFormulas = !_showFormulas),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.calculate_rounded, color: AppTheme.accentCyan, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Live Mathematical Calculations & Formulas',
                              style: TextStyle(
                                fontSize: layout.fontSize(12.5),
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : c.textPrimary,
                              ),
                            ),
                          ),
                          Icon(
                            _showFormulas ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            color: AppTheme.accentCyan,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showFormulas) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFormulaStep(
                            step: _econ.isAiPredicted
                                ? '1. ⛽ AI Predicted Fuel Consumption'
                                : '1. Fuel Needed',
                            formula: _econ.isAiPredicted
                                ? 'Multi-Output Neural Net (TFLite)'
                                : 'Distance ÷ Mileage',
                            calculation: _econ.isAiPredicted
                                ? 'Payload & friction inferred: ${_econ.fuelConsumedLiters.toStringAsFixed(2)} L'
                                : '${_econ.distanceKm.toStringAsFixed(1)} km ÷ ${_econ.vehicleMileageKmPerL.toStringAsFixed(1)} km/L',
                            result: '${_econ.fuelConsumedLiters.toStringAsFixed(2)} Liters',
                            layout: layout,
                            c: c,
                          ),
                          const SizedBox(height: 10),
                          _buildFormulaStep(
                            step: '2. Fuel Cost',
                            formula: 'Liters × Live Petrol Rate',
                            calculation:
                                '${_econ.fuelConsumedLiters.toStringAsFixed(2)} L × PKR ${_econ.fuelPricePerL.toStringAsFixed(1)}/L',
                            result: 'PKR ${_econ.fuelCost.toStringAsFixed(1)}',
                            layout: layout,
                            c: c,
                          ),
                          const SizedBox(height: 10),
                          _buildFormulaStep(
                            step: _econ.isAiPredicted
                                ? '3. 🔧 AI Route Wear & Stress'
                                : '3. Vehicle Maintenance',
                            formula: _econ.isAiPredicted
                                ? 'Neural Stress Regression'
                                : 'Distance × Wear Rate',
                            calculation: _econ.isAiPredicted
                                ? 'Stop-and-go congestion stress adjusted'
                                : '${_econ.distanceKm.toStringAsFixed(1)} km × PKR ${_econ.maintenanceRatePerKm.toStringAsFixed(1)}/km',
                            result: 'PKR ${_econ.maintenanceCost.toStringAsFixed(1)}',
                            layout: layout,
                            c: c,
                          ),
                          const SizedBox(height: 10),
                          _buildFormulaStep(
                            step: '4. Service Charges',
                            formula: 'Platform Commission Fee',
                            calculation: 'SwiftRide 0% Driver Commission Guarantee',
                            result: 'PKR 0.00',
                            layout: layout,
                            c: c,
                          ),
                          const SizedBox(height: 10),
                          _buildFormulaStep(
                            step: _econ.isAiPredicted
                                ? '5. 💰 AI Net Take-Home'
                                : '5. Net Driver Profit',
                            formula: _econ.isAiPredicted
                                ? 'Predicted Fare - (Fuel + Maint)'
                                : 'Fare - (Fuel + Maint + Fee)',
                            calculation:
                                'PKR ${_econ.totalFare.toStringAsFixed(0)} - (PKR ${_econ.fuelCost.toStringAsFixed(1)} + PKR ${_econ.maintenanceCost.toStringAsFixed(1)})',
                            result: 'PKR ${_econ.driverNetProfit.toStringAsFixed(1)} Net Profit',
                            layout: layout,
                            c: c,
                            isHighlighted: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Driver Net Profit Highlight Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.emeraldGreen.withValues(alpha: 0.18),
                    AppTheme.accentCyan.withValues(alpha: 0.12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppTheme.emeraldGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isDriverView
                              ? 'YOUR NET TAKE-HOME PROFIT'
                              : 'DRIVER NET TAKE-HOME PROFIT',
                          style: TextStyle(
                            fontSize: layout.fontSize(11),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: AppTheme.emeraldGreen,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'PKR ${_econ.driverNetProfit.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: layout.fontSize(22),
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : AppTheme.darkNavy,
                          ),
                        ),
                        Text(
                          'Earning rate: ~Rs ${_econ.profitPerMinute.toStringAsFixed(1)} / minute after all expenses',
                          style: TextStyle(
                            fontSize: layout.fontSize(11),
                            fontWeight: FontWeight.w500,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Dismiss Button
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Done',
                style: TextStyle(
                  fontSize: layout.fontSize(14),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaStep({
    required String step,
    required String formula,
    required String calculation,
    required String result,
    required ResponsiveLayoutHelper layout,
    required AppColors c,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppTheme.emeraldGreen.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: isHighlighted
            ? Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                step,
                style: TextStyle(
                  fontSize: layout.fontSize(11.5),
                  fontWeight: FontWeight.w800,
                  color: isHighlighted ? AppTheme.emeraldGreen : AppTheme.accentCyan,
                ),
              ),
              Text(
                formula,
                style: TextStyle(
                  fontSize: layout.fontSize(10),
                  fontStyle: FontStyle.italic,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                calculation,
                style: TextStyle(
                  fontSize: layout.fontSize(11),
                  fontFamily: 'monospace',
                  color: c.textPrimary,
                ),
              ),
              Text(
                result,
                style: TextStyle(
                  fontSize: layout.fontSize(11.5),
                  fontWeight: FontWeight.w800,
                  color: isHighlighted ? AppTheme.emeraldGreen : c.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required ResponsiveLayoutHelper layout,
    required AppColors c,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String trailing,
    required Color trailingColor,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: layout.fontSize(12.5),
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: layout.fontSize(10.5),
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
        Text(
          trailing,
          style: TextStyle(
            fontSize: layout.fontSize(13.5),
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            color: trailingColor,
          ),
        ),
      ],
    );
  }
}
