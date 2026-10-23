import 'package:flutter/foundation.dart';
import '../domain/models/driver_khata_model.dart';
import '../domain/models/trip_economics_model.dart';
import 'native/native_storage_service.dart';

/// Service managing the driver's daily physical cash ledger ("Khata").
/// Reconciles cash collected in pocket, deducts live fuel burned and vehicle wear reserves,
/// and persists daily records locally using [NativeStorageService].
class DriverKhataService extends ChangeNotifier {
  static final DriverKhataService _instance = DriverKhataService._internal();
  factory DriverKhataService({NativeStorageService? storage}) {
    if (storage != null) {
      _instance._storage = storage;
    }
    return _instance;
  }

  DriverKhataService._internal() {
    _initToday();
  }

  NativeStorageService _storage = NativeStorageService();

  late DriverDailyKhata _todayKhata = DriverDailyKhata(date: DateTime.now());
  DriverDailyKhata get todayKhata => _todayKhata;

  String _dateKey(DateTime dt) => 'driver_khata_${dt.year}_${dt.month}_${dt.day}';

  Future<void> _initToday() async {
    final now = DateTime.now();
    final key = _dateKey(now);
    try {
      final jsonStr = await _storage.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        _todayKhata = DriverDailyKhata.fromJson(jsonStr);
      } else {
        _todayKhata = DriverDailyKhata(date: now);
      }
    } catch (_) {
      _todayKhata = DriverDailyKhata(date: now);
    }
    notifyListeners();
  }

  /// Retrieves or initializes today's ledger, automatically rotating if a new day has arrived.
  Future<DriverDailyKhata> getTodayKhata() async {
    final now = DateTime.now();
    if (_todayKhata.date.year != now.year ||
        _todayKhata.date.month != now.month ||
        _todayKhata.date.day != now.day) {
      await _initToday();
    }
    return _todayKhata;
  }

  /// Records a completed trip into the daily ledger and commits to persistent storage.
  Future<DriverDailyKhata> recordCompletedTrip({
    required double cashCollected,
    required double fuelExpense,
    required double maintenanceReserve,
  }) async {
    await getTodayKhata();
    _todayKhata = _todayKhata.addTrip(
      cashCollected: cashCollected,
      fuelExpense: fuelExpense,
      maintenanceReserve: maintenanceReserve,
    );

    final key = _dateKey(_todayKhata.date);
    await _storage.setString(key, _todayKhata.toJson());
    notifyListeners();
    return _todayKhata;
  }

  /// Convenience method calculating fuel and wear from [TripEconomics] and committing to Khata.
  Future<DriverDailyKhata> recordTripFromEconomics(
    TripEconomics economics, {
    double? actualCashCollected,
  }) {
    final cash = actualCashCollected ?? economics.totalFare;
    return recordCompletedTrip(
      cashCollected: cash,
      fuelExpense: economics.fuelCostPkr,
      maintenanceReserve: economics.maintenanceCostPkr,
    );
  }

  /// Resets today's ledger (useful for testing or starting a fresh shift).
  Future<void> resetToday() async {
    final now = DateTime.now();
    _todayKhata = DriverDailyKhata(date: now);
    final key = _dateKey(now);
    await _storage.setString(key, _todayKhata.toJson());
    notifyListeners();
  }
}
