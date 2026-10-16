import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/models/driver_profile_model.dart';
import '../../domain/models/ride_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/ride_provider.dart';
import '../../services/native/native_audio_service.dart';
import '../../services/native/native_device_service.dart';
import '../../services/native/native_launcher_service.dart';
import '../../services/native/native_notification_service.dart';
import '../../services/pricing_ml_service.dart';
import '../../services/native_map_service.dart';
import '../../core/utils/id_generator.dart';
import '../../services/firestore/firestore_driver_service.dart';
import '../../services/map_service.dart';

/// Valuation assessment for an incoming rider bid compared to the on-device AI sweet spot.
class AiValuationAnalysis {
  final double aiValuation;
  final double differencePercent;
  final bool isLow;
  final bool isSignificantlyLow;
  final bool isFair;
  final bool isHigh;
  final String tagMessage;

  const AiValuationAnalysis({
    required this.aiValuation,
    required this.differencePercent,
    required this.isLow,
    required this.isSignificantlyLow,
    required this.isFair,
    required this.isHigh,
    required this.tagMessage,
  });
}

/// ViewModel managing Driver Cockpit UI state, PIN verification inputs,
/// counter-bidding, native hardware wake locks, and AI market valuations.
class DriverViewModel extends ChangeNotifier {
  final NativeDeviceService _deviceService;
  final FirestoreDriverService _driverService;
  final NativeNotificationService _notificationService;
  final NativeAudioService _audioService;
  final NativeLauncherService _launcherService;
  final PricingMLService _pricingMLService;

  final TextEditingController pinController = TextEditingController();
  final TextEditingController counterFareController = TextEditingController();

  String? _pinErrorMessage;
  bool _isProcessingPayout = false;
  String? _payoutIdempotencyKey;
  bool _isDisposed = false;

  final Map<String, double> _aiMarketValuations = {};
  bool _autoAcceptAiValuedRides = false;

  DriverViewModel({
    NativeDeviceService? deviceService,
    FirestoreDriverService? driverService,
    NativeNotificationService? notificationService,
    NativeAudioService? audioService,
    NativeLauncherService? launcherService,
    PricingMLService? pricingMLService,
  })  : _deviceService = deviceService ?? NativeDeviceService(),
        _driverService = driverService ?? FirestoreDriverService(),
        _notificationService = notificationService ?? NativeNotificationService(),
        _audioService = audioService ?? NativeAudioService(),
        _launcherService = launcherService ?? NativeLauncherService(),
        _pricingMLService = pricingMLService ?? PricingMLService();

  String? get pinErrorMessage => _pinErrorMessage;
  bool get isProcessingPayout => _isProcessingPayout;
  bool get autoAcceptAiValuedRides => _autoAcceptAiValuedRides;

  void toggleAutoAcceptAiValuedRides(bool value) {
    _autoAcceptAiValuedRides = value;
    notifyListeners();
  }

  /// Returns cached AI market valuation for a ride, if computed.
  double? getCachedAiValuation(String rideId) => _aiMarketValuations[rideId];

  /// Asynchronously evaluates or returns cached AI market valuation for a ride.
  Future<double> getOrCalculateAiValuation(RideModel ride) async {
    if (_aiMarketValuations.containsKey(ride.id)) {
      return _aiMarketValuations[ride.id]!;
    }

    final distance = ride.distanceKm > 0.1 ? ride.distanceKm : 5.0;
    final fare = await _pricingMLService.predictSuggestedBid(
      distanceKm: distance,
    );

    _aiMarketValuations[ride.id] = fare;
    if (!_isDisposed) {
      notifyListeners();
    }
    return fare;
  }

  final Map<String, RoutePlan> _cachedRoutePlans = {};

  /// Returns cached RoutePlan for a ride if already loaded.
  RoutePlan? getCachedRoutePlan(String rideId) => _cachedRoutePlans[rideId];

  /// Asynchronously loads or returns cached RoutePlan for a ride.
  Future<RoutePlan?> getOrFetchRoute(RideModel ride) async {
    if (_cachedRoutePlans.containsKey(ride.id)) {
      return _cachedRoutePlans[ride.id];
    }
    try {
      final origin = LatLng(ride.pickup.latitude, ride.pickup.longitude);
      final dest = LatLng(ride.dropoff.latitude, ride.dropoff.longitude);
      final plan = await MapService().fetchRoute(origin, dest);
      if (plan != null) {
        _cachedRoutePlans[ride.id] = plan;
        if (!_isDisposed) notifyListeners();
      }
      return plan;
    } catch (e) {
      debugPrint('[DriverViewModel] getOrFetchRoute error: $e');
      return null;
    }
  }

  /// Analyzes a rider's offered bid relative to the AI sweet-spot market value.
  AiValuationAnalysis analyzeFare({
    required double offeredFare,
    required double aiValuation,
  }) {
    if (aiValuation <= 0) {
      return AiValuationAnalysis(
        aiValuation: aiValuation,
        differencePercent: 0,
        isLow: false,
        isSignificantlyLow: false,
        isFair: true,
        isHigh: false,
        tagMessage: 'AI Market Value: PKR ${aiValuation.toInt()}',
      );
    }

    final diff = offeredFare - aiValuation;
    final pct = (diff / aiValuation) * 100.0;
    final isLow = pct < -7.0;
    final isSignificantlyLow = pct <= -15.0;
    final isHigh = pct > 5.0;

    String tag;
    if (isSignificantlyLow) {
      tag = 'AI Market Value: PKR ${aiValuation.toInt()} (Rider bid is ${pct.abs().toStringAsFixed(0)}% low - Counter-offer recommended)';
    } else if (isLow) {
      tag = 'AI Market Value: PKR ${aiValuation.toInt()} (Rider bid is ${pct.abs().toStringAsFixed(0)}% below market)';
    } else if (isHigh) {
      tag = 'AI Market Value: PKR ${aiValuation.toInt()} (High Value Offer +${pct.toStringAsFixed(0)}%)';
    } else {
      tag = 'AI Market Value: PKR ${aiValuation.toInt()} (Fair Market Offer)';
    }

    return AiValuationAnalysis(
      aiValuation: aiValuation,
      differencePercent: pct,
      isLow: isLow,
      isSignificantlyLow: isSignificantlyLow,
      isFair: !isLow && !isHigh,
      isHigh: isHigh,
      tagMessage: tag,
    );
  }

  /// Checks if an incoming ride qualifies for auto-acceptance within ±5% of the AI valuation.
  bool shouldAutoAccept({
    required double offeredFare,
    required double aiValuation,
  }) {
    if (!_autoAcceptAiValuedRides || aiValuation <= 0) return false;
    final diffRatio = (offeredFare - aiValuation) / aiValuation;
    // Auto-accept if offer is within -5% or above market value
    return diffRatio >= -0.05;
  }

  bool _isConfirmingCash = false;
  bool get isConfirmingCash => _isConfirmingCash;

  /// Records that the driver received cash for a completed trip.
  ///
  /// Returns an error message, or null on success.
  Future<String?> confirmCashPayment({
    required RideProvider rideProv,
    required String rideId,
  }) async {
    if (_isConfirmingCash) return null;

    _isConfirmingCash = true;
    notifyListeners();

    final error = await rideProv.confirmCashPayment(rideId);

    _isConfirmingCash = false;
    notifyListeners();
    return error;
  }

  /// Toggles driver online state and manages hardware screen wake lock.
  ///
  /// Returns an error message when the backend refused the change, so the UI can
  /// explain why instead of appearing to have gone online.
  Future<String?> toggleOnline({
    required DriverProvider driverProv,
    required LocationProvider locProv,
    required bool online,
  }) async {
    final error = await driverProv.toggleOnline(
      online,
      latitude: locProv.latitude,
      longitude: locProv.longitude,
    );

    if (error != null) {
      // Side effects (wake lock, broadcast, announcement) only run once the
      // backend confirms — otherwise the driver would be told they are online
      // while dispatch still cannot see them.
      return error;
    }

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

    // driverProv.toggleOnline already notified its listeners.
    return null;
  }

  void submitCounterOffer({
    required RideProvider rideProv,
    required DriverProfile driver,
    required String driverName,
    required String rideId,
    required double fare,
  }) {
    _deviceService.triggerHaptic('selection');
    rideProv.submitDriverCounterOffer(
      rideId: rideId,
      driver: driver,
      driverName: driverName,
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

  Future<bool> verifyPinAndStartTrip(RideProvider rideProv) async {
    final pin = pinController.text.trim();
    final success = await rideProv.startTripWithPin(pin);

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

  Future<void> completeActiveTrip({
    required RideProvider rideProv,
    required DriverProvider driverProv,
    required AuthProvider authProv,
  }) async {
    final completed = await rideProv.completeTrip();
    if (completed != null) {
      final fare = completed.acceptedFare ?? completed.offeredFare;

      // Deliberately NOT credited locally. The driver has not been paid yet — on
      // a cash trip the money is still in the rider's pocket — and earnings are
      // the backend's figure. This used to add the fare to the local balance the
      // instant the trip ended, so the cockpit reported money that had not moved.
      unawaited(driverProv.loadForUser(authProv.currentUser.id));

      authProv.incrementRidesCount();
      _deviceService.triggerHaptic('heavy');

      _notificationService.showNotification(
        id: 304,
        title: 'Trip Completed',
        body: 'PKR ${fare.toStringAsFixed(0)} is due from the rider (0% commission).',
      );
      _audioService.playAlertTone('success');
      _audioService.speak(
        'Trip completed. PKR ${fare.toInt()} is due from the rider.',
      );
    }
  }

  /// Calls the rider via native phone dialer (replaces url_launcher)
  Future<bool> callRider(String phone) async {
    return await _launcherService.launchDialer(phone);
  }

  /// Dials the local emergency number (15 — Police, Pakistan).
  Future<bool> callEmergencyServices() async {
    return await _launcherService.launchDialer('15');
  }

  /// Opens turn-by-turn navigation in native Google/Apple Maps
  Future<bool> navigateExternally(double lat, double lng) async {
    return await _launcherService.launchMapsDirections(
      destinationLat: lat,
      destinationLng: lng,
    );
  }

  /// Requests a payout through the backend ledger.
  ///
  /// [rail] is one of jazzcash / easypaisa / raast / manual; [destination] is the
  /// mobile wallet number or IBAN. Nothing is credited locally — the balance and
  /// the ledger live on the server, which also enforces idempotency.
  Future<PayoutRequestResult> requestPayout({
    required double amount,
    required String rail,
    required String destination,
  }) async {
    if (_isProcessingPayout) {
      return const PayoutRequestResult.failed('A payout is already in progress.');
    }
    if (amount <= 0) {
      return const PayoutRequestResult.failed('You have no balance to withdraw yet.');
    }

    _isProcessingPayout = true;
    notifyListeners();

    // Reuse the key across retries of the same attempt so a double tap or a
    // network retry resolves to one payout, then clear it on success so the
    // driver's next withdrawal is a genuinely new payout.
    final key = _payoutIdempotencyKey ??= IdGenerator.generate('payout');

    PayoutRequestResult result;
    try {
      result = await _driverService.requestPayout(
        amount: amount,
        rail: rail,
        destination: destination,
        idempotencyKey: key,
      );
    } catch (e) {
      debugPrint('[DriverViewModel] payout failed: $e');
      result = const PayoutRequestResult.failed(
        'We could not start your payout. Your balance is unchanged.',
      );
    }

    if (result.accepted) {
      _payoutIdempotencyKey = null;
      await _deviceService.triggerHaptic('heavy');
    }

    _isProcessingPayout = false;
    notifyListeners();
    return result;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _deviceService.setKeepScreenOn(false);
    pinController.dispose();
    counterFareController.dispose();
    super.dispose();
  }
}
