import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/ad_service.dart';
import '../../services/native/native_storage_service.dart';

/// Reusable non-blocking Native Advanced Ad card widget.
///
/// Designed for scrollable content feeds (e.g. RideHistoryScreen, DriverKhataSheet).
/// Styled dynamically to match Swift Ride's dark and light surfaces and typography.
/// Safely degrades to [SizedBox.shrink] on web, desktop, test runners, or when no ad fills.
class NativeAdCardWidget extends StatefulWidget {
  final EdgeInsetsGeometry margin;

  const NativeAdCardWidget({
    super.key,
    this.margin = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  State<NativeAdCardWidget> createState() => _NativeAdCardWidgetState();
}

class _NativeAdCardWidgetState extends State<NativeAdCardWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoaded && !_isLoading && _nativeAd == null) {
      _initAndLoadAd();
    }
  }

  Future<void> _initAndLoadAd() async {
    if (kIsWeb || _isLoading || _nativeAd != null) return;
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
      _loadNativeAd();
    } catch (e) {
      _isLoading = false;
      debugPrint('[NativeAdCardWidget] Initialization error: $e');
    }
  }

  void _loadNativeAd() {
    if (kIsWeb || !mounted || _nativeAd != null) {
      _isLoading = false;
      return;
    }

    try {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final c = Theme.of(context).extension<AppColors>() ??
          (isDark ? AppColors.dark : AppColors.light);

      final unitId = AdService.instance.nativeAdUnitId;
      debugPrint('[NativeAdCardWidget] Loading NativeAd with adUnitId: $unitId (debug=$kDebugMode)');

      final cardBg = isDark ? const Color(0xFF141B2D) : Colors.white;
      final primaryText = isDark ? Colors.white : c.textPrimary;
      final secondaryText = isDark ? const Color(0xFF94A3B8) : c.textSecondary;
      final tertiaryText = isDark ? const Color(0xFF64748B) : c.textMuted;

      _nativeAd = NativeAd(
        adUnitId: unitId,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.small,
          mainBackgroundColor: cardBg,
          cornerRadius: 16.0,
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: primaryText,
            size: 14.0,
            style: NativeTemplateFontStyle.bold,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: secondaryText,
            size: 12.0,
            style: NativeTemplateFontStyle.normal,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: tertiaryText,
            size: 10.0,
            style: NativeTemplateFontStyle.normal,
          ),
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            backgroundColor: AppTheme.primaryBlue,
            size: 13.0,
            style: NativeTemplateFontStyle.bold,
          ),
        ),
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            debugPrint('[NativeAdCardWidget] Native ad loaded (${ad.responseInfo?.responseId}). Rendering card.');
            _isLoading = false;
            if (mounted) {
              setState(() => _isLoaded = true);
            }
          },
          onAdImpression: (ad) {
            debugPrint('[NativeAdCardWidget] Native ad impression recorded (${ad.responseInfo?.responseId}).');
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('[NativeAdCardWidget] Native ad failed to load: code=${error.code}, message=${error.message}');
            ad.dispose();
            _nativeAd = null;
            _isLoading = false;
            if (mounted) {
              setState(() => _isLoaded = false);
            }
          },
        ),
      )..load();
    } catch (e) {
      _isLoading = false;
      debugPrint('[NativeAdCardWidget] Native ad create error: $e');
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    _nativeAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = Theme.of(context).extension<AppColors>() ??
        (isDark ? AppColors.dark : AppColors.light);

    return Container(
      key: const Key('native_ad_card'),
      margin: widget.margin,
      constraints: const BoxConstraints(
        minHeight: 90,
        maxHeight: 120,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141B2D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: c.border.withValues(alpha: isDark ? 0.3 : 0.6),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 100,
        child: AdWidget(ad: _nativeAd!),
      ),
    );
  }
}
