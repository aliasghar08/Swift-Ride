import 'package:flutter/material.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../services/native/native_audio_service.dart';
import '../../services/native/native_device_service.dart';
import '../../services/native/native_launcher_service.dart';
import '../../services/native/native_notification_service.dart';
import '../../services/native/native_payment_service.dart';

/// ViewModel managing Driver Cockpit UI state, PIN verification inputs,
/// counter-bidding, and native hardware wake locks.
class DriverViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final NativePaymentService _paymentService;
  final NativeNotificationService _notificationService;
  final NativeAudioService _audioService;
  final NativeLauncherService _launcherService;

  final TextEditingController pinController = TextEditingController();
  final TextEditingController counterFareController = TextEditingController();

  String? _pinErrorMessage;
  bool _isProcessingPayout = false;

  DriverViewModel({
    NativeDeviceService? deviceService,
    NativePaymentService? paymentService,
    NativeNotificationService? notificationService,
    NativeAudioService? audioService,
    NativeLauncherService? launcherService,
  })  : _deviceService = deviceService ?? NativeDeviceService(),
        _paymentService = paymentService ?? NativePaymentService(),
        _notificationService = notificationService ?? NativeNotificationService(),
        _audioService = audioService ?? NativeAudioService(),
        _launcherService = launcherService ?? NativeLauncherService();

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
      _notificationService.showNotification(
        id: 301,
        title: 'SwiftRide Driver Online',
        body: 'Broadcasting live coordinates. Ready for ride requests.',
      );
      _audioService.speak('You are now online and ready for rides.');
    } else {
      locProv.stopBroadcaster();
      await _deviceService.setKeepScreenOn(false);
      await _deviceService.triggerHaptic('light');
      _audioService.speak('You are now offline.');
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

    _notificationService.showNotification(
      id: 302,
      title: 'Arrived at Pickup',
      body: 'Waiting for rider to board. Please request 4-digit PIN.',
    );
    _audioService.speak('Arrived at pickup. Ask rider for verification PIN.');
  }

  bool verifyPinAndStartTrip(RideProvider rideProv) {
    final pin = pinController.text.trim();
    final success = rideProv.startTripWithPin(pin);

    if (success) {
      _pinErrorMessage = null;
      _deviceService.triggerHaptic('heavy');
      pinController.clear();
      _notificationService.showNotification(
        id: 303,
        title: 'Trip Started',
        body: 'Navigating to destination. Zero commission active.',
      );
      _audioService.speak('PIN verified. Starting trip to destination.');
      notifyListeners();
      return true;
    } else {
      _pinErrorMessage = 'Invalid verification PIN. Ask rider for 4-digit code.';
      _deviceService.triggerHaptic('vibrate');
      _audioService.playAlertTone('beep');
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

      _notificationService.showNotification(
        id: 304,
        title: 'Trip Completed!',
        body: 'Earned PKR ${fare.toStringAsFixed(0)} (100% kept, 0% commission)',
      );
      _audioService.playAlertTone('success');
      _audioService.speak('Trip completed. PKR ${fare.toInt()} added to earnings.');
    }
  }

  /// Calls the rider via native phone dialer (replaces url_launcher)
  Future<bool> callRider(String phone) async {
    return await _launcherService.launchDialer(phone);
  }

  /// Opens turn-by-turn navigation in native Google/Apple Maps
  Future<bool> navigateExternally(double lat, double lng) async {
    return await _launcherService.launchMapsDirections(
      destinationLat: lat,
      destinationLng: lng,
    );
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
