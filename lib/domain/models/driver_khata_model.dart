import 'dart:convert';

/// Daily financial ledger ("Khata") for drivers, tracking physical cash collected,
/// live fuel burn deductions, and vehicle wear/maintenance reserves.
class DriverDailyKhata {
  final DateTime date;
  final int completedTrips;
  final double totalGrossCashCollected;
  final double totalFuelExpense;
  final double totalMaintenanceReserve;
  final double platformFeeRate;

  const DriverDailyKhata({
    required this.date,
    this.completedTrips = 0,
    this.totalGrossCashCollected = 0.0,
    this.totalFuelExpense = 0.0,
    this.totalMaintenanceReserve = 0.0,
    this.platformFeeRate = 0.02,
  });

  /// Platform commission deduction (0% if fee waiver active, else 2%).
  double get platformCommission =>
      ((totalGrossCashCollected * platformFeeRate) * 10).round() / 10.0;

  /// True if 0% fee waiver is active on this ledger.
  bool get isWaiverActive => platformFeeRate <= 0.0;

  /// Net take-home cash profit retained by the driver after live fuel & wear reserves and fee.
  double get netCashProfit =>
      totalGrossCashCollected - (totalFuelExpense + totalMaintenanceReserve + platformCommission);

  DriverDailyKhata copyWith({
    DateTime? date,
    int? completedTrips,
    double? totalGrossCashCollected,
    double? totalFuelExpense,
    double? totalMaintenanceReserve,
    double? platformFeeRate,
  }) {
    return DriverDailyKhata(
      date: date ?? this.date,
      completedTrips: completedTrips ?? this.completedTrips,
      totalGrossCashCollected:
          totalGrossCashCollected ?? this.totalGrossCashCollected,
      totalFuelExpense: totalFuelExpense ?? this.totalFuelExpense,
      totalMaintenanceReserve:
          totalMaintenanceReserve ?? this.totalMaintenanceReserve,
      platformFeeRate: platformFeeRate ?? this.platformFeeRate,
    );
  }

  /// Adds a completed trip's cash, fuel expense, and maintenance reserve to this day's ledger.
  DriverDailyKhata addTrip({
    required double cashCollected,
    required double fuelExpense,
    required double maintenanceReserve,
    double? feeRate,
  }) {
    return DriverDailyKhata(
      date: date,
      completedTrips: completedTrips + 1,
      totalGrossCashCollected: totalGrossCashCollected + cashCollected,
      totalFuelExpense: totalFuelExpense + fuelExpense,
      totalMaintenanceReserve: totalMaintenanceReserve + maintenanceReserve,
      platformFeeRate: feeRate ?? platformFeeRate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'completedTrips': completedTrips,
      'totalGrossCashCollected': totalGrossCashCollected,
      'totalFuelExpense': totalFuelExpense,
      'totalMaintenanceReserve': totalMaintenanceReserve,
      'netCashProfit': netCashProfit,
      'platformFeeRate': platformFeeRate,
    };
  }

  factory DriverDailyKhata.fromMap(Map<String, dynamic> map) {
    return DriverDailyKhata(
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      completedTrips: (map['completedTrips'] as num?)?.toInt() ?? 0,
      totalGrossCashCollected:
          (map['totalGrossCashCollected'] as num?)?.toDouble() ?? 0.0,
      totalFuelExpense: (map['totalFuelExpense'] as num?)?.toDouble() ?? 0.0,
      totalMaintenanceReserve:
          (map['totalMaintenanceReserve'] as num?)?.toDouble() ?? 0.0,
      platformFeeRate: (map['platformFeeRate'] as num?)?.toDouble() ?? 0.02,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DriverDailyKhata.fromJson(String source) =>
      DriverDailyKhata.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
