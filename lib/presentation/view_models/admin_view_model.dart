import 'package:flutter/material.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../providers/admin_provider.dart';
import '../../services/native/native_device_service.dart';

/// ViewModel managing Admin Dashboard search filters, operational approvals,
/// and responsive table interactions.
class AdminViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  String _searchQuery = '';
  String _timeRange = 'All Time';

  AdminViewModel({NativeDeviceService? deviceService})
      : _deviceService = deviceService ?? NativeDeviceService();

  String get searchQuery => _searchQuery;
  String get timeRange => _timeRange;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setTimeRange(String range) {
    _timeRange = range;
    _deviceService.triggerHaptic('selection');
    notifyListeners();
  }

  List<DriverProfile> filterDrivers(List<DriverProfile> drivers) {
    if (_searchQuery.trim().isEmpty) return drivers;
    final q = _searchQuery.toLowerCase();
    return drivers.where((d) {
      return d.userId.toLowerCase().contains(q) ||
          d.licenseNumber.toLowerCase().contains(q) ||
          d.vehicle.plate.toLowerCase().contains(q) ||
          d.vehicle.model.toLowerCase().contains(q);
    }).toList();
  }

  /// Sends a verification decision to the backend.
  ///
  /// Returns true only when the server confirmed it; the caller must surface a
  /// failure rather than assuming the application was actioned.
  Future<bool> processDriverVerification({
    required AdminProvider adminProv,
    required String driverId,
    required bool approve,
  }) async {
    await _deviceService.triggerHaptic(approve ? 'heavy' : 'light');
    return adminProv.verifyDriver(driverId, approve);
  }
}
