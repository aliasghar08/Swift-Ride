import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import '../../domain/models/trip_economics_model.dart';
import '../../services/driver_khata_service.dart';
import '../view_models/responsive_layout_helper.dart';

class ExactChangeResult {
  final double cashReceived;
  final double changeDue;
  final bool isTipped;
  final double netCashCollected;

  const ExactChangeResult({
    required this.cashReceived,
    required this.changeDue,
    required this.isTipped,
    required this.netCashCollected,
  });
}

/// Interactive cash assistant dialog helping drivers calculate exact change
/// on Pakistani Rupee (PKR) currency notes and record net collections into Khata.
class ExactChangeDialog extends StatefulWidget {
  final double fare;
  final TripEconomics? tripEconomics;
  final double? fuelExpense;
  final double? maintenanceReserve;
  final Future<void> Function(ExactChangeResult result)? onConfirm;

  const ExactChangeDialog({
    super.key,
    required this.fare,
    this.tripEconomics,
    this.fuelExpense,
    this.maintenanceReserve,
    this.onConfirm,
  });

  static Future<ExactChangeResult?> show(
    BuildContext context, {
    required double fare,
    TripEconomics? tripEconomics,
    double? fuelExpense,
    double? maintenanceReserve,
    Future<void> Function(ExactChangeResult result)? onConfirm,
  }) {
    return showDialog<ExactChangeResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExactChangeDialog(
        fare: fare,
        tripEconomics: tripEconomics,
        fuelExpense: fuelExpense,
        maintenanceReserve: maintenanceReserve,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<ExactChangeDialog> createState() => _ExactChangeDialogState();
}

class _ExactChangeDialogState extends State<ExactChangeDialog> {
  late double _cashReceived;
  bool _riderTippedChange = false;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    _cashReceived = widget.fare;
  }

  double get _changeDue {
    final diff = _cashReceived - widget.fare;
    return diff > 0 ? diff : 0.0;
  }

  double get _effectiveCashForKhata {
    // If rider tips the change, the driver retains the full cash received
    if (_riderTippedChange) {
      return _cashReceived;
    }
    return widget.fare;
  }

  void _selectNote(double noteAmount) {
    setState(() {
      _cashReceived = noteAmount;
      if (_changeDue == 0) {
        _riderTippedChange = false;
      }
    });
  }

  Future<void> _handleConfirm() async {
    setState(() => _isCommitting = true);
    final result = ExactChangeResult(
      cashReceived: _cashReceived,
      changeDue: _changeDue,
      isTipped: _riderTippedChange,
      netCashCollected: _effectiveCashForKhata,
    );

    // Commit to local DriverDailyKhata
    try {
      final khataService = DriverKhataService();
      final fuel = widget.fuelExpense ?? widget.tripEconomics?.fuelCostPkr ?? 0.0;
      final maint = widget.maintenanceReserve ?? widget.tripEconomics?.maintenanceCostPkr ?? 0.0;

      await khataService.recordCompletedTrip(
        cashCollected: _effectiveCashForKhata,
        fuelExpense: fuel,
        maintenanceReserve: maint,
      );

      if (widget.onConfirm != null) {
        await widget.onConfirm!(result);
      }
    } catch (e) {
      debugPrint('[ExactChangeDialog] Error committing to Khata: $e');
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
        Navigator.of(context).pop(result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);

    final List<double> notes = [
      widget.fare,
      if (widget.fare <= 500) 500.0,
      if (widget.fare <= 1000) 1000.0,
      5000.0,
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: EdgeInsets.all(layout.scale(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.currency_exchange_rounded,
                    color: AppTheme.emeraldGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exact Change Assistant',
                        style: TextStyle(
                          fontSize: layout.fontSize(16),
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : c.textPrimary,
                        ),
                      ),
                      Text(
                        'Collect Cash: ${CurrencyFormatter.format(widget.fare)}',
                        style: TextStyle(
                          fontSize: layout.fontSize(13),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.emeraldGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Note Selector Label
            Text(
              'Cash Handed by Passenger:',
              style: TextStyle(
                fontSize: layout.fontSize(12),
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 10),

            // Quick Note Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: notes.map((note) {
                final isSelected = (_cashReceived - note).abs() < 0.01;
                final isExact = (note - widget.fare).abs() < 0.01;
                final label = isExact
                    ? 'Exact: PKR ${note.toInt()}'
                    : 'PKR ${note.toInt()} Note';

                return SizedBox(
                  height: layout.touchTarget(42),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isSelected
                          ? AppTheme.accentCyan.withValues(alpha: 0.15)
                          : c.surfaceRaised,
                      side: BorderSide(
                        color: isSelected ? AppTheme.accentCyan : c.border,
                        width: isSelected ? 2 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => _selectNote(note),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected
                            ? AppTheme.accentCyan
                            : (isDark ? Colors.white : c.textPrimary),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Change Due Display Box
            if (_changeDue > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.amberWarning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.amberWarning.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Wapas Karein (Return Change):',
                          style: TextStyle(
                            fontSize: layout.fontSize(12),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.amberWarning,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(_changeDue),
                          style: TextStyle(
                            fontSize: layout.fontSize(20),
                            fontWeight: FontWeight.w900,
                            color: AppTheme.amberWarning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // Tip Toggle
                    Row(
                      children: [
                        const Icon(
                          Icons.volunteer_activism_rounded,
                          size: 18,
                          color: AppTheme.emeraldGreen,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Rider tipped change (${CurrencyFormatter.format(_changeDue)})',
                            style: TextStyle(
                              fontSize: layout.fontSize(11.5),
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : c.textPrimary,
                            ),
                          ),
                        ),
                        Switch(
                          value: _riderTippedChange,
                          activeThumbColor: AppTheme.emeraldGreen,
                          onChanged: (val) {
                            setState(() => _riderTippedChange = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.emeraldGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.emeraldGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Exact cash received. No change required.',
                        style: TextStyle(
                          fontSize: layout.fontSize(12),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.emeraldGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Confirm Button
            SizedBox(
              height: layout.touchTarget(48),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emeraldGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isCommitting ? null : _handleConfirm,
                child: _isCommitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _riderTippedChange
                            ? 'Commit PKR ${_cashReceived.toInt()} to Khata'
                            : 'Confirm & Commit to Khata',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
