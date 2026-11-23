import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../services/ad_service.dart';

/// Reusable non-intrusive adaptive banner ad widget.
///
/// Automatically hides itself if uninitialized, failing to load, or running on
/// unsupported environments (web, desktop, or test harnesses).
class AdBannerWidget extends StatefulWidget {
  final EdgeInsetsGeometry padding;

  const AdBannerWidget({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  int _retryAttempt = 0;
  Timer? _retryTimer;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initAndLoadBanner();
  }

  Future<void> _initAndLoadBanner() async {
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
    } catch (_) {
      return;
    }

    try {
      await AdService.instance.ensureInitialized();
      if (!mounted) return;
      _loadBanner();
    } catch (e) {
      debugPrint('[AdBannerWidget] Initialization error: $e');
    }
  }

  void _loadBanner() {
    if (kIsWeb || !mounted) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      _createBannerAd();
    } catch (e) {
      debugPrint('[AdBannerWidget] Banner load error: $e');
    }
  }

  void _createBannerAd() {
    if (kIsWeb || !mounted || _bannerAd != null) return;
    try {
      final unitId = AdService.instance.bannerAdUnitId;
      debugPrint('[AdBannerWidget] Creating BannerAd with adUnitId: $unitId (debug=$kDebugMode)');
      _bannerAd = BannerAd(
        adUnitId: unitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('[AdBannerWidget] Banner ad loaded successfully (${ad.responseInfo?.responseId}). Rendering widget.');
            _retryAttempt = 0;
            if (mounted) {
              setState(() => _isLoaded = true);
              _scheduleRefresh();
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdBannerWidget] Banner failed to load: code=${error.code}, message=${error.message}');
            ad.dispose();
            _bannerAd = null;
            if (mounted) {
              setState(() => _isLoaded = false);
              _scheduleRetry();
            }
          },
        ),
      )..load();
    } catch (e) {
      debugPrint('[AdBannerWidget] Banner create error: $e');
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delaySeconds = (2 << _retryAttempt).clamp(2, 60);
    _retryAttempt = (_retryAttempt + 1).clamp(0, 5);
    debugPrint('[AdBannerWidget] Scheduling ad reload in ${delaySeconds}s (attempt $_retryAttempt)');
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted) {
        _createBannerAd();
      }
    });
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        _refreshBannerAd();
      }
    });
  }

  void _refreshBannerAd() {
    if (kIsWeb || !mounted) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
      final unitId = AdService.instance.bannerAdUnitId;
      late final BannerAd nextAd;
      nextAd = BannerAd(
        adUnitId: unitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('[AdBannerWidget] Rotated banner ad loaded successfully.');
            if (mounted) {
              final oldAd = _bannerAd;
              setState(() {
                _bannerAd = nextAd;
                _isLoaded = true;
              });
              oldAd?.dispose();
              _scheduleRefresh();
            } else {
              nextAd.dispose();
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdBannerWidget] Rotated banner failed to load: ${error.message}');
            nextAd.dispose();
            if (mounted) {
              _scheduleRefresh();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

