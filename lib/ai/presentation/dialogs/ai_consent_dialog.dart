import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../presentation/common/legal_terms_modal.dart';
import '../../../services/native/native_storage_service.dart';

/// Lightweight SharedPreferences facade backed by [NativeStorageService]
/// (Android SharedPreferences / iOS UserDefaults via MethodChannel with
/// synchronous in-memory caching for deterministic widget testing).
class SharedPreferences {
  static final Map<String, dynamic> _memoryCache = {};
  final NativeStorageService _storage;

  SharedPreferences._(this._storage);

  static Future<SharedPreferences> getInstance() async {
    return SharedPreferences._(NativeStorageService());
  }

  bool? getBool(String key) => _memoryCache[key] as bool? ?? _storage.peekBoolSync(key);

  Future<bool?> getBoolAsync(String key) async {
    final syncVal = getBool(key);
    if (syncVal != null) return syncVal;
    try {
      final asyncVal = await _storage.getBool(key);
      if (asyncVal != null) {
        _memoryCache[key] = asyncVal;
      }
      return asyncVal;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setBool(String key, bool value) async {
    _memoryCache[key] = value;
    try {
      // Fire-and-forget persist to native storage without blocking UI thread / test runner
      _storage.setBool(key, value);
    } catch (_) {}
    return true;
  }
}

/// Apple App Store Guideline 5.1.1(i) & 5.1.2(i) Compliance Dialog.
///
/// Explicitly discloses third-party AI data sharing (Google Gemini AI via
/// Firebase AI Logic) and obtains explicit user permission before any
/// personal or contextual data is transmitted off-device.
class AiConsentDialog extends StatelessWidget {
  static const String consentKey = 'ai_data_consent_granted';

  /// Reactive notifier so Profile / Settings toggles stay in sync across the app.
  static final ValueNotifier<bool> consentNotifier = ValueNotifier<bool>(false);

  static bool _initializedFromDisk = false;

  const AiConsentDialog({super.key});

  /// Synchronously returns the cached consent state (defaults to `false`).
  static bool isConsentGrantedSync() {
    return consentNotifier.value;
  }

  /// Reads persisted consent state from `SharedPreferences` (`ai_data_consent_granted`).
  /// Defaults to `false` until the user explicitly taps "Agree & Continue".
  static Future<bool> isConsentGranted() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(consentKey);
    if (cached != null) {
      consentNotifier.value = cached;
      return cached;
    }
    if (!_initializedFromDisk) {
      _initializedFromDisk = true;
      final stored = await prefs.getBoolAsync(consentKey);
      if (stored != null) {
        consentNotifier.value = stored;
        return stored;
      }
    }
    return consentNotifier.value;
  }

  /// Persists the user's AI data-sharing consent choice (`true` or `false`).
  static Future<void> setConsent(bool granted) async {
    _initializedFromDisk = true;
    consentNotifier.value = granted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentKey, granted);
  }

  /// Ensures explicit user consent has been granted before any cloud AI call runs.
  ///
  /// Returns `true` immediately if already granted; otherwise displays the
  /// modal disclosure dialog and returns `true` only if the user taps
  /// "Agree & Continue".
  static Future<bool> ensureConsent(BuildContext context) async {
    final alreadyGranted = await isConsentGranted();
    if (alreadyGranted) return true;

    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AiConsentDialog(),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor =
        isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08);
    final textPrimary = isDark ? Colors.white : AppTheme.darkNavy;
    final textSecondary = isDark ? Colors.white70 : AppTheme.slateMuted;

    return AlertDialog(
      backgroundColor: bgColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.privacy_tip_rounded,
              color: AppTheme.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Data Sharing Permission',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Apple Guideline 5.1.1(i) & 5.1.2(i) Disclosure',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Before using SwiftRide cloud AI features, please review how your data is processed:',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _buildDisclosureTile(
              icon: Icons.cloud_outlined,
              title: 'Recipient',
              body: 'Google LLC (via Google Gemini AI / Firebase AI Logic).',
              cardColor: cardColor,
              borderColor: borderColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            const SizedBox(height: 8),
            _buildDisclosureTile(
              icon: Icons.data_object_rounded,
              title: 'Data Sent',
              body:
                  'Your chat messages, user role (Rider/Driver), active trip route metrics (distance, duration, fare), and vehicle status needed to generate responses or safety check-ins.',
              cardColor: cardColor,
              borderColor: borderColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            const SizedBox(height: 8),
            _buildDisclosureTile(
              icon: Icons.lock_outline_rounded,
              title: 'Protection & Control',
              body:
                  'Data is encrypted in transit, used strictly for in-app assistance, and never sold. You can decline and continue using all core ride-hailing features (powered by on-device pricing) without cloud AI.',
              cardColor: cardColor,
              borderColor: borderColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => LegalTermsModal.showPrivacy(context),
                icon: const Icon(Icons.description_outlined, size: 15),
                label: const Text(
                  'Read Full Privacy Policy',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('ai_consent_decline_btn'),
                onPressed: () async {
                  await setConsent(false);
                  if (context.mounted) {
                    Navigator.of(context).pop(false);
                  }
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Decline',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                key: const Key('ai_consent_agree_btn'),
                onPressed: () async {
                  await setConsent(true);
                  if (context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Agree & Continue',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDisclosureTile({
    required IconData icon,
    required String title,
    required String body,
    required Color cardColor,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
