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

  bool _initialized = false;
  bool _initializing = false;
  bool get isInitialized => _initialized;

  InterstitialAd? _postRideInterstitial;
  bool _isLoadingInterstitial = false;

  /// Initializes the Google Mobile Ads SDK safely in the background.
  Future<void> initialize() async {
    if (kIsWeb || _initialized || _initializing) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      _initializing = true;
      debugPrint('[AdService] Starting background MobileAds initialization...');
      final initStatus = await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint('[AdService] MobileAds initialized successfully. Adapters count: ${initStatus.adapterStatuses.length}');
      initStatus.adapterStatuses.forEach((key, status) {
        debugPrint('[AdService] Adapter [$key]: state=${status.state}, desc=${status.description}');
      });

      // Delay interstitial preloading by 10 seconds so it never contends with initial app interaction
      Future.delayed(const Duration(seconds: 10), () {
        debugPrint('[AdService] Triggering background preloading of post-ride interstitial ad...');
        loadPostRideInterstitial();
      });
    } catch (e) {
      debugPrint('[AdService] MobileAds initialization skipped or failed: $e');
    } finally {
      _initializing = false;
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

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return Platform.isAndroid
        ? liveAndroidInterstitialId
        : 'ca-app-pub-3940256099942544/4411468910';
  }

  /// Preloads a post-trip interstitial ad in the background.
  void loadPostRideInterstitial() {
    if (!_initialized || kIsWeb || _isLoadingInterstitial || _postRideInterstitial != null) {
      debugPrint('[AdService] Skip interstitial load: initialized=$_initialized, loading=$_isLoadingInterstitial, ready=${_postRideInterstitial != null}');
      return;
    }
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      _isLoadingInterstitial = true;
      debugPrint('[AdService] Loading interstitial ad (Unit ID: $interstitialAdUnitId)...');

      InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _isLoadingInterstitial = false;
            _postRideInterstitial = ad;
            debugPrint('[AdService] Interstitial ad loaded successfully into memory.');
            _postRideInterstitial?.fullScreenContentCallback =
                FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                debugPrint('[AdService] Interstitial ad dismissed by user. Disposing and reloading.');
                ad.dispose();
                _postRideInterstitial = null;
                loadPostRideInterstitial();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                debugPrint('[AdService] Interstitial ad failed to show: ${error.message}. Reloading.');
                ad.dispose();
                _postRideInterstitial = null;
                loadPostRideInterstitial();
              },
            );
          },
          onAdFailedToLoad: (error) {
            _isLoadingInterstitial = false;
            _postRideInterstitial = null;
            debugPrint('[AdService] Interstitial failed to load: code=${error.code}, message=${error.message}');
          },
        ),
      );
    } catch (e) {
      _isLoadingInterstitial = false;
      debugPrint('[AdService] Interstitial load exception: $e');
    }
  }

  /// Displays the post-ride completion interstitial if preloaded.
  void showPostRideInterstitial({VoidCallback? onDismissed}) {
    if (_postRideInterstitial != null) {
      debugPrint('[AdService] Displaying preloaded post-ride interstitial ad.');
      final ad = _postRideInterstitial!;
      if (onDismissed != null) {
        final prevCallback = ad.fullScreenContentCallback;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            prevCallback?.onAdDismissedFullScreenContent?.call(ad);
            onDismissed();
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            prevCallback?.onAdFailedToShowFullScreenContent?.call(ad, err);
            onDismissed();
          },
        );
      }
      ad.show();
      _postRideInterstitial = null;
    } else {
      debugPrint('[AdService] No interstitial preloaded; proceeding immediately without ad.');
      onDismissed?.call();
    }
  }
}
