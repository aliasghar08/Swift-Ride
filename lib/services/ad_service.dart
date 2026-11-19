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

  bool _initialized = false;
  bool get isInitialized => _initialized;

  InterstitialAd? _postRideInterstitial;
  bool _isLoadingInterstitial = false;

  /// Initializes the Google Mobile Ads SDK safely.
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      await MobileAds.instance.initialize();
      _initialized = true;
      loadPostRideInterstitial();
    } catch (e) {
      debugPrint('[AdService] MobileAds initialization skipped or failed: $e');
    }
  }

  /// Official Google test Ad Unit IDs during development;
  /// replace with production AdMob Ad Unit IDs for release builds.
  String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111' // Replace with prod Android Banner ID
        : 'ca-app-pub-3940256099942544/2934735716'; // Replace with prod iOS Banner ID
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/1033173712' // Replace with prod Android Interstitial ID
        : 'ca-app-pub-3940256099942544/4411468910'; // Replace with prod iOS Interstitial ID
  }

  /// Preloads a post-trip interstitial ad in the background.
  void loadPostRideInterstitial() {
    if (!_initialized || kIsWeb || _isLoadingInterstitial || _postRideInterstitial != null) {
      return;
    }
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      _isLoadingInterstitial = true;

      InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _isLoadingInterstitial = false;
            _postRideInterstitial = ad;
            _postRideInterstitial?.fullScreenContentCallback =
                FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                _postRideInterstitial = null;
                loadPostRideInterstitial();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                _postRideInterstitial = null;
                loadPostRideInterstitial();
              },
            );
          },
          onAdFailedToLoad: (error) {
            _isLoadingInterstitial = false;
            _postRideInterstitial = null;
            debugPrint('[AdService] Interstitial failed to load: ${error.message}');
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
      onDismissed?.call();
    }
  }
}
