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
  Timer? _deferTimer;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _scheduleLoadBanner();
  }

  void _scheduleLoadBanner() {
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
    } catch (_) {
      return;
    }

    if (AdService.instance.isInitialized) {
      _loadBanner();
    } else {
      // Wait for deferred AdMob initialization so Chromium WebView never blocks cold startup
      _deferTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) _loadBanner();
      });
    }
  }

  void _loadBanner() {
    if (kIsWeb || !mounted) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;

      _bannerAd = BannerAd(
        adUnitId: AdService.instance.bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _isLoaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[AdBannerWidget] Banner failed to load: ${error.message}');
            ad.dispose();
            if (mounted) setState(() => _isLoaded = false);
          },
        ),
      )..load();
    } catch (e) {
      debugPrint('[AdBannerWidget] Banner load error: $e');
    }
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
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

