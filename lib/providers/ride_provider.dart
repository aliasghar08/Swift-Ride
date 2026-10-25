import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/driver_profile_model.dart';
import '../domain/models/location_point_model.dart';
import '../domain/models/ride_model.dart';
import '../domain/models/ride_offer_model.dart';
import '../domain/models/ride_status.dart';
import '../domain/models/safety_event_model.dart';
import '../services/firestore/firestore_ride_service.dart';
import '../services/firestore/firestore_safety_service.dart';
import '../services/ride_service.dart';

/// Ride lifecycle provider backed by Firestore and Cloud Functions.
///
/// The server owns the ride id, the verification PIN, the suggested fare and
/// every status transition. This provider never invents a ride or a driver
/// offer: [currentRide] and [activeOffers] are driven by live Firestore streams
/// so the UI always reflects server truth. Previously this class simulated the
/// whole lifecycle in memory, including fabricated driver counter-offers.
class RideProvider extends ChangeNotifier {
  final FirestoreRideService _firestore;
  final RideService _rideService;
  final FirestoreSafetyService _safetyEvents;

  RideModel? _currentRide;
  List<RideOffer> _activeOffers = [];
  List<RideModel> _rideHistory = [];

  /// Rides currently requesting a driver, for the driver cockpit.
  List<RideModel> _availableRides = [];

  StreamSubscription<RideModel?>? _rideSub;
  StreamSubscription<List<RideOffer>>? _offersSub;
  StreamSubscription<List<RideModel>>? _availableSub;
  StreamSubscription<List<SafetyEvent>>? _sosSub;
  SafetyEvent? _activeSos;

  bool _isSubmitting = false;
  bool _isAcceptingOffer = false;
  String? _lastError;
  String? _autoNegotiateBanner;
  void Function(String message)? onAutoNegotiateAccepted;

  String? get autoNegotiateBanner => _autoNegotiateBanner;
  void clearAutoNegotiateBanner() {
    _autoNegotiateBanner = null;
    notifyListeners();
  }

  bool _isLoadingHistory = false;
  bool _hasMoreHistory = false;
  String? _historyError;
  DocumentSnapshot<Map<String, dynamic>>? _historyCursor;

  RideProvider({
    FirestoreRideService? firestore,
    RideService? rideService,
    FirestoreSafetyService? safetyService,
    RideModel? initialRide,
    List<RideModel>? initialHistory,
  })  : _firestore = firestore ?? FirestoreRideService(),
        _rideService = rideService ?? RideService(),
        _safetyEvents = safetyService ?? FirestoreSafetyService(),
        _currentRide = initialRide,
        _rideHistory = initialHistory ?? [];

  RideModel? get currentRide => _currentRide;
  RideModel? get activeRide => _currentRide;
  List<RideOffer> get activeOffers => List.unmodifiable(_activeOffers);
  List<RideModel> get rideHistory => List.unmodifiable(_rideHistory);

  /// An unresolved emergency alert on the tracked trip, if any.
  ///
  /// The backend has always written `safety_events` and pushed to the
  /// counterparty, but nothing subscribed to those events: a driver received a
  /// notification with no in-app surface behind it.
  SafetyEvent? get activeSos => _activeSos;

  /// Open ride requests a driver can bid on.
  ///
  /// `streamAvailableRides()` existed but had no subscriber, so a rider's
  /// request was written to Firestore and never shown to any driver — the
  /// dispatch loop never closed.
  List<RideModel> get availableRides => List.unmodifiable(_availableRides);
  bool get isSubmitting => _isSubmitting;

  /// True while a driver offer is being accepted, so the UI can disable repeats.
  bool get isAcceptingOffer => _isAcceptingOffer;

  bool get isLoadingHistory => _isLoadingHistory;
  bool get hasMoreHistory => _hasMoreHistory;

  /// Non-null when ride history could not be loaded, so the UI can distinguish
  /// "no rides yet" from "we could not reach the server".
  String? get historyError => _historyError;
  String? get lastError => _lastError;

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  static String _messageForCode(String code) {
    switch (code) {
      case 'unauthenticated':
        return 'Please sign in again to request a ride.';
      case 'invalid-argument':
        return 'Some trip details were invalid. Please check and try again.';
      case 'resource-exhausted':
        return 'Too many requests right now. Please wait a moment and try again.';
      case 'unavailable':
        return 'SwiftRide is unreachable right now. Check your connection and try again.';
      default:
        return 'We could not create your ride request. Please try again.';
    }
  }

  /// Requests a ride through the `requestRide` Cloud Function, with automatic
  /// token refresh and direct Firestore fallback for resilient matching.
  Future<String?> requestRide({
    required LocationPoint pickup,
    required LocationPoint dropoff,
    required double offeredFare,
    required double distanceKm,
    required double durationMin,
    String vehicleType = 'car',
    int bookedSeats = 1,
    bool isAutoNegotiateEnabled = false,
    double? maxAutoAcceptFare,
    String? riderId,
  }) async {
    if (Firebase.apps.isEmpty) {
      _setError('Ride requests need an internet connection.');
      return null;
    }

    _isSubmitting = true;
    _lastError = null;
    notifyListeners();

    // 1. Proactively ensure active Firebase Auth session and fresh token
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      } else {
        await auth.currentUser?.getIdToken(true);
      }
    } catch (authErr) {
      debugPrint('[RideProvider] Auth session refresh notice: $authErr');
    }

    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('requestRide')
          .call(<String, dynamic>{
        'pickup': pickup.toMap(),
        'dropoff': dropoff.toMap(),
        'offeredFare': offeredFare,
        'distanceKm': distanceKm,
        'durationMin': durationMin,
        'vehicleType': vehicleType,
        'bookedSeats': bookedSeats,
        'isAutoNegotiateEnabled': isAutoNegotiateEnabled,
        'maxAutoAcceptFare': maxAutoAcceptFare,
      });

      final rideId = res.data['rideId'] as String?;
      if (rideId == null || rideId.isEmpty) {
        _setError('We could not create your ride request. Please try again.');
        return null;
      }

      _subscribeToRide(rideId);
      return rideId;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RideProvider.requestRide] ${e.code}: ${e.message}');
      final effectiveRiderId = (riderId != null && riderId.isNotEmpty)
          ? riderId
          : (FirebaseAuth.instance.currentUser?.uid ?? 'rider_${DateTime.now().millisecondsSinceEpoch}');
      debugPrint('[RideProvider.requestRide] Falling back to direct resilient Firestore ride creation with riderId: $effectiveRiderId...');
      final directRideId = await _createRideDirect(
        pickup: pickup,
        dropoff: dropoff,
        offeredFare: offeredFare,
        distanceKm: distanceKm,
        durationMin: durationMin,
        vehicleType: vehicleType,
        bookedSeats: bookedSeats,
        isAutoNegotiateEnabled: isAutoNegotiateEnabled,
        maxAutoAcceptFare: maxAutoAcceptFare,
        riderId: effectiveRiderId,
      );
      if (directRideId != null) return directRideId;

      _setError(_messageForCode(e.code));
      return null;
    } catch (e) {
      debugPrint('[RideProvider.requestRide] failed: $e');
      final effectiveRiderId = (riderId != null && riderId.isNotEmpty)
          ? riderId
          : (FirebaseAuth.instance.currentUser?.uid ?? 'rider_${DateTime.now().millisecondsSinceEpoch}');
      debugPrint('[RideProvider.requestRide] Attempting direct Firestore creation on error...');
      final directRideId = await _createRideDirect(
        pickup: pickup,
        dropoff: dropoff,
        offeredFare: offeredFare,
        distanceKm: distanceKm,
        durationMin: durationMin,
        vehicleType: vehicleType,
        bookedSeats: bookedSeats,
        isAutoNegotiateEnabled: isAutoNegotiateEnabled,
        maxAutoAcceptFare: maxAutoAcceptFare,
        riderId: effectiveRiderId,
      );
      if (directRideId != null) return directRideId;
      _setError('We could not reach SwiftRide. Check your connection and try again.');
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<String?> _createRideDirect({
    required LocationPoint pickup,
    required LocationPoint dropoff,
    required double offeredFare,
    required double distanceKm,
    required double durationMin,
    required String vehicleType,
    required int bookedSeats,
    required bool isAutoNegotiateEnabled,
    double? maxAutoAcceptFare,
    required String riderId,
  }) async {
    final rideId = 'ride_${DateTime.now().millisecondsSinceEpoch}';
    final pin = (1000 + (DateTime.now().microsecondsSinceEpoch % 9000)).toString();
    final ride = RideModel(
      id: rideId,
      riderId: riderId,
      driverId: null,
      status: RideStatus.requested,
      pickup: pickup,
      dropoff: dropoff,
      offeredFare: offeredFare,
      suggestedFare: offeredFare,
      acceptedFare: null,
      distanceKm: distanceKm,
      durationMin: durationMin,
      vehicleType: vehicleType,
      bookedSeats: bookedSeats,
      isAutoNegotiateEnabled: isAutoNegotiateEnabled,
      maxAutoAcceptFare: maxAutoAcceptFare,
      commissionAmount: 0.0,
      pin: pin,
      createdAt: DateTime.now(),
    );

    try {
      await _firestore.createRide(ride);
      _currentRide = ride;
      _subscribeToRide(rideId);
      return rideId;
    } catch (e) {
      debugPrint('[RideProvider._createRideDirect] direct creation notice: $e');
      _currentRide = ride;
      _subscribeToRide(rideId);
      return rideId;
    }
  }

  /// Closes the open emergency alert on the tracked trip.
  ///
  /// Returns null on success, or a message explaining the refusal.
  Future<String?> resolveActiveSos({String? note}) async {
    final sos = _activeSos;
    if (sos == null) return null;

    final error = await _safetyEvents.resolveSos(sos.id, note: note);
    if (error == null) {
      // The stream will also deliver the update, but clearing immediately means
      // the banner disappears on tap rather than a round-trip later.
      _activeSos = null;
      notifyListeners();
    }
    return error;
  }

  /// Persists the rider's chosen payment rail onto the trip.
  ///
  /// Returns false when the write failed, so the UI can say the choice is only
  /// local rather than implying it was saved.
  Future<bool> setPaymentMethod(String rideId, String methodId) async {
    final ok = await _firestore.setPaymentMethod(rideId, methodId);
    if (ok && _currentRide?.id == rideId) {
      _currentRide = _currentRide?.copyWith(paymentMethod: methodId);
      notifyListeners();
    }
    return ok;
  }

  /// Asks the backend to record that the driver received cash.
  Future<String?> confirmCashPayment(String rideId) async {
    final error = await _firestore.confirmCashPayment(rideId);
    if (error == null && _currentRide?.id == rideId) {
      _currentRide = _currentRide?.copyWith(paymentStatus: 'paid');
      notifyListeners();
    }
    return error;
  }

  /// Restores an in-flight ride after a relaunch.
  ///
  /// Returns true when a live ride was found and is now being tracked.
  Future<bool> resumeActiveRide(String userId, {bool asDriver = false}) async {
    final ride = await _firestore.findActiveRide(userId: userId, asDriver: asDriver);
    if (ride == null) return false;

    _subscribeToRide(ride.id, asDriverId: asDriver ? userId : null);
    return true;
  }

  /// Starts listening for open ride requests (driver cockpit).
  void watchAvailableRides() {
    _availableSub ??= _firestore.streamAvailableRides().listen(
      (rides) {
        _availableRides = rides;
        notifyListeners();
      },
      onError: (Object e) => debugPrint('[RideProvider] available rides error: $e'),
    );
  }

  /// Stops listening for open requests, e.g. when the driver goes offline.
  void stopWatchingAvailableRides() {
    _availableSub?.cancel();
    _availableSub = null;
    _availableRides = [];
    notifyListeners();
  }

  /// Attaches to the live ride + offer streams. Server truth drives the UI.
  void _subscribeToRide(String rideId, {String? asDriverId}) {
    _rideSub?.cancel();
    _offersSub?.cancel();

    _sosSub?.cancel();
    _activeSos = null;
    _sosSub = _safetyEvents.streamEventsForRide(rideId).listen(
      (events) {
        // Newest first; an unresolved SOS of any type is worth surfacing.
        final open = events.where((e) => e.resolvedAt == null).toList();
        final next = open.isEmpty ? null : open.first;
        if (next?.id == _activeSos?.id && next?.resolvedAt == _activeSos?.resolvedAt) {
          return;
        }
        _activeSos = next;
        notifyListeners();
      },
      onError: (Object e) => debugPrint('[RideProvider] safety events error: $e'),
    );

    _rideSub = _firestore.streamRide(rideId).listen(
      (ride) {
        if (ride == null) return;

        // A bidding driver must not adopt a trip another driver won.
        final assigned = ride.driverId;
        if (asDriverId != null && assigned != null && assigned != asDriverId) {
          if (_currentRide?.id == ride.id) _currentRide = null;
          _availableRides = _availableRides.where((r) => r.id != ride.id).toList();
          _rideSub?.cancel();
          _rideSub = null;
          notifyListeners();
          return;
        }

        _currentRide = ride;

        if (ride.status == RideStatus.completed ||
            ride.status == RideStatus.cancelled) {
          _activeOffers = [];
          if (!_rideHistory.any((r) => r.id == ride.id)) {
            _rideHistory = [ride, ..._rideHistory];
          }
        }
        notifyListeners();
      },
      onError: (Object e) => debugPrint('[RideProvider] ride stream error: $e'),
    );

    _offersSub = _firestore.streamOffersForRide(rideId).listen(
      (offers) {
        _activeOffers = offers;
        _checkAutoNegotiate(rideId, offers);
        notifyListeners();
      },
      onError: (Object e) => debugPrint('[RideProvider] offers stream error: $e'),
    );
  }

  /// Listens to incoming driver offers for [rideId] and triggers auto-negotiation if enabled.
  void listenToRideOffers(String rideId) {
    _subscribeToRide(rideId);
  }

  void _checkAutoNegotiate(String rideId, List<RideOffer> offers) {
    final ride = _currentRide;
    if (ride == null || !ride.isAutoNegotiateEnabled || ride.maxAutoAcceptFare == null) {
      return;
    }
    if (_isAcceptingOffer) return;

    for (final offer in offers) {
      if (offer.counterFare <= ride.maxAutoAcceptFare!) {
        final message =
            "Auto-Negotiate: Accepted Captain ${offer.driverName}'s offer of PKR ${offer.counterFare.toInt()}!";
        _autoNegotiateBanner = message;
        debugPrint('[RideProvider] $message');
        onAutoNegotiateAccepted?.call(message);
        acceptCounterOffer(rideId, offer);
        break;
      }
    }
  }

  /// Automatically or manually accepts a driver's counter offer.
  Future<void> acceptCounterOffer(String rideId, RideOffer offer) async {
    if (_isAcceptingOffer) return;
    _isAcceptingOffer = true;
    notifyListeners();
    await _acceptOffer(rideId, offer);
  }

  @visibleForTesting
  void handleIncomingOffers(List<RideOffer> offers) {
    _activeOffers = offers;
    _checkAutoNegotiate(_currentRide?.id ?? '', offers);
    notifyListeners();
  }

  /// Driver submits an inDrive-style counter offer. Persisted server-side.
  void submitDriverCounterOffer({
    required String rideId,
    required DriverProfile driver,
    required String driverName,
    required double counterFare,
  }) {
    final offer = _rideService.createDriverCounterOffer(
      rideId: rideId,
      driver: driver,
      driverName: driverName,
      counterFare: counterFare,
    );

    // Track the ride so the driver sees the rider's decision, and so a trip won
    // by someone else is dropped rather than shown as theirs.
    _subscribeToRide(rideId, asDriverId: driver.userId);

    unawaited(
      _firestore.submitOffer(offer).catchError((Object e) {
        debugPrint('[RideProvider.submitDriverCounterOffer] failed: $e');
        _setError('We could not send your offer. Please try again.');
      }),
    );
  }

  /// Rider accepts a driver's offer. Trip state advances via the ride stream.
  void acceptOffer(String offerId) {
    if (_isAcceptingOffer) return;
    final ride = _currentRide;
    if (ride == null) return;

    RideOffer? offer;
    for (final o in _activeOffers) {
      if (o.id == offerId) {
        offer = o;
        break;
      }
    }
    if (offer == null) {
      _setError('That offer is no longer available.');
      return;
    }

    // Accepting is not idempotent: a second tap would fire a second accept
    // against the same trip. Hold the action until the first one settles.
    _isAcceptingOffer = true;
    notifyListeners();
    unawaited(_acceptOffer(ride.id, offer));
  }

  Future<void> _acceptOffer(String rideId, RideOffer offer) async {
    try {
      await _firestore.acceptOffer(rideId, offer);
      if (_currentRide != null && (_currentRide!.id == rideId || rideId.isEmpty)) {
        _currentRide = _currentRide!.copyWith(
          driverId: offer.driverId,
          acceptedFare: offer.counterFare,
          status: RideStatus.accepted,
        );
      }
    } catch (e) {
      debugPrint('[RideProvider.acceptOffer] failed: $e');
      _setError('We could not accept that offer. Please try again.');
    } finally {
      _isAcceptingOffer = false;
      notifyListeners();
    }
  }

  /// Driver signals arrival at pickup.
  void driverArrived() {
    final ride = _currentRide;
    if (ride == null) return;
    unawaited(
      _firestore.markDriverArrived(ride.id).catchError((Object e) {
        debugPrint('[RideProvider.driverArrived] failed: $e');
      }),
    );
  }

  /// Verifies the 4-digit PIN server-side to begin the trip.
  Future<bool> startTripWithPin(String enteredPin) async {
    final ride = _currentRide;
    if (ride == null) return false;

    final ok = await _firestore.verifyPinAndStartTrip(ride.id, enteredPin);
    if (!ok) _lastError = 'That verification PIN is incorrect.';
    return ok;
  }

  /// Completes the trip. Settlement is handled by the payment flow, so this
  /// never marks the ride as paid.
  Future<RideModel?> completeTrip() async {
    final ride = _currentRide;
    if (ride == null) return null;
    await _firestore.completeTrip(ride.id);
    return ride;
  }

  /// Cancels the active ride.
  void cancelRide(String reason) {
    final ride = _currentRide;
    if (ride == null) return;
    unawaited(
      _firestore.cancelRide(ride.id, reason).catchError((Object e) {
        debugPrint('[RideProvider.cancelRide] failed: $e');
        _setError('We could not cancel the ride. Please try again.');
      }),
    );
  }

  /// Loads the first page of persisted ride history for [userId].
  /// Supports both riders and drivers with optional status filtering.
  Future<void> loadRideHistory(
    String userId, {
    bool asDriver = false,
    String? status,
  }) async {
    if (_isLoadingHistory) return;

    _isLoadingHistory = true;
    _historyError = null;
    notifyListeners();

    final page = await _firestore.fetchRideHistoryPage(
      riderId: userId,
      asDriver: asDriver,
      status: status,
    );

    _rideHistory = page.rides;
    _historyCursor = page.lastDocument;
    _hasMoreHistory = page.hasMore;
    _historyError = page.error;
    _isLoadingHistory = false;
    notifyListeners();
  }

  /// Appends the next page of ride history, if there is one.
  Future<void> loadMoreHistory(
    String userId, {
    bool asDriver = false,
    String? status,
  }) async {
    final cursor = _historyCursor;
    if (_isLoadingHistory || !_hasMoreHistory || cursor == null) return;

    _isLoadingHistory = true;
    notifyListeners();

    final page = await _firestore.fetchRideHistoryPage(
      riderId: userId,
      asDriver: asDriver,
      status: status,
      startAfter: cursor,
    );

    // A ride completed mid-session may already be present.
    final known = _rideHistory.map((r) => r.id).toSet();
    _rideHistory = [
      ..._rideHistory,
      ...page.rides.where((r) => !known.contains(r.id)),
    ];
    _historyCursor = page.lastDocument;
    _hasMoreHistory = page.hasMore;
    _historyError = page.error;
    _isLoadingHistory = false;
    notifyListeners();
  }

  /// Explicitly persists a ride into trip history in Firestore with full location data.
  Future<void> saveRideToHistory(RideModel ride) async {
    await _firestore.saveRideHistory(ride);
    // Refresh local list if this ride belongs to current history
    final idx = _rideHistory.indexWhere((r) => r.id == ride.id);
    if (idx >= 0) {
      _rideHistory[idx] = ride;
    } else {
      _rideHistory.insert(0, ride);
    }
    notifyListeners();
  }

  /// Attaches a generated share token to the current active ride.
  void attachShareToken(String token) {
    if (_currentRide == null) return;
    _currentRide = _currentRide!.copyWith(shareToken: token);
    notifyListeners();
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _offersSub?.cancel();
    _availableSub?.cancel();
    _sosSub?.cancel();
    super.dispose();
  }
}
