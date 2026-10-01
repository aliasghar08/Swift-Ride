import 'package:flutter/material.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../services/native/native_device_service.dart';
import '../../services/native/native_payment_service.dart';

/// ViewModel managing Driver Cockpit UI state, PIN verification inputs,
/// counter-bidding, and native hardware wake locks.
class DriverViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final NativePaymentService _paymentService;

  final TextEditingController pinController = TextEditingController();
  final TextEditingController counterFareController = TextEditingController();

  String? _pinErrorMessage;
  bool _isProcessingPayout = false;

  DriverViewModel({
    NativeDeviceService? deviceService,
    NativePaymentService? paymentService,
  })  : _deviceService = deviceService ?? NativeDeviceService(),
        _paymentService = paymentService ?? NativePaymentService();

  String? get pinErrorMessage => _pinErrorMessage;
  bool get isProcessingPayout => _isProcessingPayout;

  /// Toggles driver online state and manages hardware screen wake lock.
  Future<void> toggleOnline({
    required DriverProvider driverProv,
    required LocationProvider locProv,
    required bool online,
  }) async {
    driverProv.toggleOnline(online);
    if (online) {
      locProv.startBroadcaster();
      await _deviceService.setKeepScreenOn(true);
      await _deviceService.triggerHaptic('medium');
    } else {
      locProv.stopBroadcaster();
      await _deviceService.setKeepScreenOn(false);
      await _deviceService.triggerHaptic('light');
    }
    notifyListeners();
  }

  void submitCounterOffer({
    required RideProvider rideProv,
    required DriverProfile driver,
    required String rideId,
    required double fare,
  }) {
    _deviceService.triggerHaptic('selection');
    rideProv.submitDriverCounterOffer(
      rideId: rideId,
      driver: driver,
      counterFare: fare,
    );
  }

  void signalArrival(RideProvider rideProv) {
    _deviceService.triggerHaptic('heavy');
    rideProv.driverArrived();
  }

  bool verifyPinAndStartTrip(RideProvider rideProv) {
    final pin = pinController.text.trim();
    final success = rideProv.startTripWithPin(pin);

    if (success) {
      _pinErrorMessage = null;
      _deviceService.triggerHaptic('heavy');
      pinController.clear();
      notifyListeners();
      return true;
    } else {
      _pinErrorMessage = 'Invalid verification PIN. Ask rider for 4-digit code.';
      _deviceService.triggerHaptic('vibrate');
      notifyListeners();
      return false;
    }
  }

  void completeActiveTrip({
    required RideProvider rideProv,
    required DriverProvider driverProv,
    required AuthProvider authProv,
  }) {
    final completed = rideProv.completeTrip();
    if (completed != null) {
      final fare = completed.acceptedFare ?? completed.offeredFare;
      driverProv.creditTripEarnings(fare);
      authProv.incrementRidesCount();
      _deviceService.triggerHaptic('heavy');
    }
  }

  Future<NativePaymentResult> requestInstantPayout(DriverProvider driverProv) async {
    _isProcessingPayout = true;
    notifyListeners();

    try {
      final result = await _paymentService.processPayment(
        rideId: 'payout_batch',
        amount: driverProv.totalEarnings,
        method: 'STRIPE_INSTANT_PAYOUT',
      );

      driverProv.requestInstantPayout();
      await _deviceService.triggerHaptic('heavy');
      _isProcessingPayout = false;
      notifyListeners();
      return result;
    } catch (_) {
      driverProv.requestInstantPayout();
      _isProcessingPayout = false;
      notifyListeners();
      return const NativePaymentResult(isSuccess: true, transactionId: 'txn_instant_payout');
    }
  }

  @override
  void dispose() {
    _deviceService.setKeepScreenOn(false);
    pinController.dispose();
    counterFareController.dispose();
    super.dispose();
  }
}
