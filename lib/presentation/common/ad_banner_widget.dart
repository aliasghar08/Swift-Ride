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

  void _createBannerAd({bool useFallback = false}) {
    if (kIsWeb || !mounted || _bannerAd != null) return;
    try {
      final unitId = useFallback
          ? AdService.testAndroidBannerId
          : AdService.instance.bannerAdUnitId;
      debugPrint('[AdBannerWidget] Creating BannerAd with adUnitId: $unitId (fallback=$useFallback)');
      _bannerAd = BannerAd(
        adUnitId: unitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            debugPrint('[AdBannerWidget] Banner ad loaded successfully (${ad.responseInfo?.responseId}). Rendering widget.');
            if (mounted) setState(() => _isLoaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdBannerWidget] Banner failed to load: code=${error.code}, message=${error.message}');
            ad.dispose();
            _bannerAd = null;
            // If live ad failed with no inventory (Code 3) or not yet filled, fallback to sample banner
            if (!useFallback && unitId != AdService.testAndroidBannerId) {
              debugPrint('[AdBannerWidget] Live ad unfilled (code ${error.code}); falling back to Google sample banner ad to verify display.');
              _createBannerAd(useFallback: true);
              return;
            }
            if (mounted) setState(() => _isLoaded = false);
          },
        ),
      )..load();
    } catch (e) {
      debugPrint('[AdBannerWidget] Banner create error: $e');
    }
  }

  @override
  void dispose() {
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

