import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../domain/models/ride_status.dart';
import '../domain/models/user_role.dart';
import 'native/native_storage_service.dart';

/// Centralized ad visibility policy for Swift Ride.
///
/// Core Rule:
/// Ads are shown on EVERY screen, EXCEPT when isDriverMode == true AND the driver
/// is actively driving:
/// - Has an active trip in [RideStatus.accepted], [RideStatus.driverArrived], or [RideStatus.inProgress]
/// - OR has the turn-by-turn navigation HUD / route actively running.
class AdVisibilityPolicy {
  AdVisibilityPolicy._();

  /// Evaluates whether an ad should be displayed given user role, active ride status,
  /// and navigation state.
  static bool shouldShowAds({
    required UserRole? role,
    RideStatus? tripStatus,
    bool isNavigationActive = false,
    bool isSosActive = false,
    bool isDriverMode = false,
  }) {
    // Safety critical: emergency SOS hides ads for all users
    if (isSosActive) return false;

    // Admin dashboard: strictly no ads
    if (role == UserRole.admin) return false;

    // Driver Mode check: hide ONLY while actively driving a trip or navigating
    final isDriver = isDriverMode || role == UserRole.driver;
    if (isDriver) {
      if (isNavigationActive) return false;
      if (tripStatus != null) {
        if (tripStatus == RideStatus.accepted ||
            tripStatus == RideStatus.driverArrived ||
            tripStatus == RideStatus.inProgress) {
          return false;
        }
      }
    }

    // All Rider screens (idle, searching, bidding, active trip, history, profile),
    // Auth, Onboarding, Settings, Vehicle Setup, Verification, Khata,
    // and idle Drivers all show ads.
    return true;
  }
}

/// Centralized manager for Google AdMob in Swift Ride.
///
/// Follows non-intrusive ad placement rules:
/// - Ads are strictly prohibited during active driver navigation, fare negotiation,
///   and emergency SOS flows.
/// - Adaptive banners only appear on static idle sheets (destination picker, khata summary).
/// - Interstitials are disabled in favor of non-intrusive adaptive banners and native cards.
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

  /// Exponential backoff delay schedule: 2s -> 5s -> 15s (max 3 retries).
  static const List<int> retryBackoffSeconds = [2, 5, 15];

  bool _initialized = false;
  bool get isInitialized => _initialized;
  Future<void>? _initFuture;

  BannerAd? _prewarmedBannerAd;
  bool _isPrewarming = false;
  int _prewarmRetryCount = 0;
  Timer? _prewarmRetryTimer;

  BannerAd? get prewarmedBannerAd => _prewarmedBannerAd;

  /// Returns and detaches the pre-warmed banner ad instance so a widget can mount it.
  BannerAd? consumePrewarmedBannerAd() {
    final ad = _prewarmedBannerAd;
    _prewarmedBannerAd = null;
    return ad;
  }

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

      // Background pre-warm first banner for instant zero-latency display
      prewarmBannerAd();
    } catch (e) {
      debugPrint('[AdService] MobileAds initialization skipped or failed: $e');
    }
  }

  /// Pre-warms a loaded [BannerAd] in memory ahead of screen transitions.
  Future<void> prewarmBannerAd({int? width}) async {
    if (kIsWeb || _isPrewarming || _prewarmedBannerAd != null) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      if (NativeStorageService.isTestEnvironment) return;
    } catch (_) {
      return;
    }

    _isPrewarming = true;
    try {
      await ensureInitialized();
      final unitId = bannerAdUnitId;
      AdSize size = AdSize.banner;
      if (width != null && width > 0) {
        try {
          // ignore: deprecated_member_use
          final adaptive = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
          if (adaptive != null) size = adaptive;
        } catch (_) {}
      }

      late final BannerAd prewarmAd;
      prewarmAd = BannerAd(
        adUnitId: unitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('[AdService] Pre-warmed banner ad loaded successfully (${ad.responseInfo?.responseId}).');
            _prewarmedBannerAd = prewarmAd;
            _prewarmRetryCount = 0;
            _isPrewarming = false;
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdService] Pre-warmed banner failed to load: code=${error.code}, domain=${error.domain}, message=${error.message}');
            ad.dispose();
            _prewarmedBannerAd = null;
            _isPrewarming = false;
            _schedulePrewarmRetry(width: width, error: error);
          },
        ),
      );
      prewarmAd.load();
    } catch (e) {
      _isPrewarming = false;
      debugPrint('[AdService] Banner prewarm error: $e');
    }
  }

  void _schedulePrewarmRetry({int? width, LoadAdError? error}) {
    if (NativeStorageService.isTestEnvironment) return;
    _prewarmRetryTimer?.cancel();
    if (_prewarmRetryCount >= retryBackoffSeconds.length) {
      debugPrint('[AdService] Max banner prewarm retries reached ($_prewarmRetryCount). Halting prewarm.');
      return;
    }
    final delaySeconds = retryBackoffSeconds[_prewarmRetryCount];
    _prewarmRetryCount++;
    debugPrint('[AdService] Scheduling banner prewarm reload in ${delaySeconds}s (attempt $_prewarmRetryCount/${retryBackoffSeconds.length}, code=${error?.code}, domain=${error?.domain})');
    _prewarmRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      prewarmBannerAd(width: width);
    });
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
