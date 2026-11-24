import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../services/ad_service.dart';
import '../../services/native/native_storage_service.dart';

/// Reusable non-intrusive adaptive banner ad widget.
///
/// Automatically hides itself if uninitialized, failing to load, or running on
/// unsupported environments (web, desktop, or test harnesses).
/// Employs anchored adaptive ad sizing and guards against redundant loads on
/// viewInset / keyboard fluctuations.
class AdBannerWidget extends StatefulWidget {
  final EdgeInsetsGeometry padding;

  const AdBannerWidget({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  int? _loadedWidth;
  int _retryAttempt = 0;
  Timer? _retryTimer;
  Timer? _refreshTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width > 0 && width != _loadedWidth && !_isLoading && _bannerAd == null) {
      _initAndLoadBanner(width);
    }
  }

  Future<void> _initAndLoadBanner(int width) async {
    if (kIsWeb || _isLoading) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
    } catch (_) {
      return;
    }

    if (NativeStorageService.isTestEnvironment) {
      return;
    }

    _isLoading = true;
    try {
      await AdService.instance.ensureInitialized();
      if (!mounted) {
        _isLoading = false;
        return;
      }
      await _createBannerAd(width);
    } catch (e) {
      _isLoading = false;
      debugPrint('[AdBannerWidget] Initialization error: $e');
    }
  }

  Future<void> _createBannerAd(int width) async {
    if (kIsWeb || !mounted || _bannerAd != null) {
      _isLoading = false;
      return;
    }

    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        _isLoading = false;
        return;
      }
      if (NativeStorageService.isTestEnvironment) {
        _isLoading = false;
        return;
      }

      final unitId = AdService.instance.bannerAdUnitId;
      debugPrint('[AdBannerWidget] Creating anchored adaptive banner for width=$width (adUnitId: $unitId)');

      AdSize? adaptiveSize;
      try {
        // ignore: deprecated_member_use
        adaptiveSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      } catch (e) {
        debugPrint('[AdBannerWidget] Error querying anchored adaptive banner size: $e');
      }
      final size = adaptiveSize ?? AdSize.banner;

      if (!mounted) {
        _isLoading = false;
        return;
      }

      _bannerAd = BannerAd(
        adUnitId: unitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('[AdBannerWidget] Banner ad loaded successfully (${ad.responseInfo?.responseId}). Rendering widget.');
            _retryAttempt = 0;
            _isLoading = false;
            _loadedWidth = width;
            if (mounted) {
              setState(() => _isLoaded = true);
              _scheduleRefresh(width);
            }
          },
          onAdImpression: (ad) {
            debugPrint('[AdBannerWidget] Banner impression recorded (${ad.responseInfo?.responseId}).');
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdBannerWidget] Banner failed to load: code=${error.code}, message=${error.message}');
            ad.dispose();
            _bannerAd = null;
            _isLoading = false;
            if (mounted) {
              setState(() => _isLoaded = false);
              _handleLoadFailure(error.code, width);
            }
          },
        ),
      )..load();
    } catch (e) {
      _isLoading = false;
      debugPrint('[AdBannerWidget] Banner create error: $e');
    }
  }

  void _handleLoadFailure(int errorCode, int width) {
    if (NativeStorageService.isTestEnvironment) return;
    _retryTimer?.cancel();
    if (_retryAttempt >= 3) {
      debugPrint('[AdBannerWidget] Max retries reached ($_retryAttempt). Halting re-requests.');
      return;
    }

    // Controlled backoff on NO_FILL (3): 30s, 60s, 120s
    final delaySeconds = errorCode == 3
        ? [30, 60, 120][_retryAttempt]
        : (2 << _retryAttempt).clamp(10, 60);

    _retryAttempt++;
    debugPrint('[AdBannerWidget] Scheduling ad reload in ${delaySeconds}s (attempt $_retryAttempt/3, error code: $errorCode)');
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && _bannerAd == null && !_isLoading) {
        _createBannerAd(width);
      }
    });
  }

  void _scheduleRefresh(int width) {
    if (NativeStorageService.isTestEnvironment) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        _refreshBannerAd(width);
      }
    });
  }

  Future<void> _refreshBannerAd(int width) async {
    if (kIsWeb || !mounted) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      if (NativeStorageService.isTestEnvironment) return;

      final unitId = AdService.instance.bannerAdUnitId;

      AdSize? adaptiveSize;
      try {
        // ignore: deprecated_member_use
        adaptiveSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      } catch (_) {}
      final size = adaptiveSize ?? AdSize.banner;

      late final BannerAd nextAd;
      nextAd = BannerAd(
        adUnitId: unitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('[AdBannerWidget] Rotated banner ad loaded successfully (${ad.responseInfo?.responseId}).');
            if (mounted) {
              final oldAd = _bannerAd;
              setState(() {
                _bannerAd = nextAd;
                _isLoaded = true;
                _loadedWidth = width;
              });
              oldAd?.dispose();
              _scheduleRefresh(width);
            } else {
              nextAd.dispose();
            }
          },
          onAdImpression: (ad) {
            debugPrint('[AdBannerWidget] Rotated banner impression recorded (${ad.responseInfo?.responseId}).');
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdBannerWidget] Rotated banner failed to load: ${error.message}');
            nextAd.dispose();
            if (mounted) {
              _scheduleRefresh(width);
            }
          },
        ),
      );
      nextAd.load();
    } catch (e) {
      debugPrint('[AdBannerWidget] Banner refresh error: $e');
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _refreshTimer?.cancel();
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: Center(
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }
}
