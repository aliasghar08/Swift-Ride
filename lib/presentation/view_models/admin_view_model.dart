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

  void processDriverVerification({
    required AdminProvider adminProv,
    required String driverId,
    required bool approve,
  }) {
    if (approve) {
      _deviceService.triggerHaptic('heavy');
    } else {
      _deviceService.triggerHaptic('light');
    }
    adminProv.verifyDriver(driverId, approve);
  }
}
