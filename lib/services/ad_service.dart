import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Centralized manager for Google AdMob in Swift Ride.
///
/// Follows non-intrusive ad placement rules:
/// - Ads are strictly prohibited during active driver navigation, fare negotiation,
///   and emergency SOS flows.
/// - Adaptive banners only appear on static idle sheets (destination picker, khata summary).
/// - Interstitials only trigger after a completed ride has been dismissed.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const String liveAndroidBannerId = 'ca-app-pub-9402443776639153/2568735153';
  static const String liveAndroidInterstitialId = 'ca-app-pub-9402443776639153/3739839885';
  static const String liveAndroidNativeId = 'ca-app-pub-9402443776639153/2980008128';

  static const String testAndroidBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String testAndroidInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String testAndroidNativeId = 'ca-app-pub-3940256099942544/2247696110';
  static const String testIosNativeId = 'ca-app-pub-3940256099942544/3986624511';

  bool _initialized = false;
  bool get isInitialized => _initialized;
  Future<void>? _initFuture;

  /// Exposes SDK readiness directly so widgets can await without polling or sleeping.
  Future<void> ensureInitialized() => initialize();

  /// Initializes the Google Mobile Ads SDK safely in the background (idempotent).
  Future<void> initialize() {
    if (kIsWeb) return Future.value();
    if (_initialized) return Future.value();
    if (_initFuture != null) return _initFuture!;

    _initFuture = _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      debugPrint('[AdService] Starting non-blocking MobileAds initialization...');
      final initStatus = await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint('[AdService] MobileAds initialized successfully. Adapters count: ${initStatus.adapterStatuses.length}');
      initStatus.adapterStatuses.forEach((key, status) {
        debugPrint('[AdService] Adapter [$key]: state=${status.state}, desc=${status.description}');
      });

      // Interstitial preloading disabled (banner-only mode).
    } catch (e) {
      debugPrint('[AdService] MobileAds initialization skipped or failed: $e');
    }
  }

  /// Official Google test Ad Unit IDs during development (to prevent invalid traffic strikes);
  /// live AdMob Ad Unit IDs in release mode.
  String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return Platform.isAndroid
        ? liveAndroidBannerId
        : 'ca-app-pub-3940256099942544/2934735716';
  }

  String get nativeAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? testAndroidNativeId
          : testIosNativeId;
    }
    return Platform.isAndroid
        ? liveAndroidNativeId
        : testIosNativeId;
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? testAndroidInterstitialId
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return Platform.isAndroid
        ? liveAndroidInterstitialId
        : 'ca-app-pub-3940256099942544/4411468910';
  }

  /// Interstitials are disabled across Swift Ride (banner + native only).
  void loadPostRideInterstitial() {
    debugPrint('[AdService] Interstitials disabled: banner + native only mode active.');
  }

  /// Displays the post-ride completion interstitial if preloaded (disabled: banner + native only).
  void showPostRideInterstitial({VoidCallback? onDismissed}) {
    debugPrint('[AdService] Interstitials disabled: proceeding immediately without ad.');
    onDismissed?.call();
  }
}
