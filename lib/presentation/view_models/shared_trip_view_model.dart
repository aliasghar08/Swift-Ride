import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../domain/models/ride_model.dart';
import '../../services/native/native_device_service.dart';

/// ViewModel managing Shared Trip public tracking display and ETA metrics.
class SharedTripViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final String? token;
  bool _isCopied = false;

  SharedTripViewModel({
    this.token,
    NativeDeviceService? deviceService,
  }) : _deviceService = deviceService ?? NativeDeviceService();

  bool get isCopied => _isCopied;

  Future<void> copyShareLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _isCopied = true;
    await _deviceService.triggerHaptic('selection');
    notifyListeners();

    await Future.delayed(const Duration(seconds: 3));
    _isCopied = false;
    notifyListeners();
  }

  int estimateRemainingMinutes(RideModel? ride) {
    if (ride == null) return 8;
    return (ride.durationMin * 0.7).round();
  }
}
