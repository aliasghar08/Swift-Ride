import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../services/native/native_storage_service.dart';

/// Google Play "Prominent Disclosure & Consent" dialog.
///
/// Shown IMMEDIATELY before an OS runtime permission prompt. The OS prompt is
/// launched from inside the "Continue" button's `onPressed` callback, so there
/// is no screen transition or delay between the disclosure and the system
/// dialog. "Not Now" dismisses cleanly without ever launching the OS prompt.
///
/// The dialog is not dismissible by tapping outside or with the back button,
/// so the user always makes an explicit choice.
class ProminentDisclosureDialog extends StatefulWidget {
  const ProminentDisclosureDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onContinue,
    this.bullets = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> bullets;

  /// Invoked synchronously from the "Continue" tap. Must call the OS runtime
  /// permission request directly and return whether it was granted.
  final Future<bool> Function() onContinue;

  /// Shows the disclosure. Returns `true` only if the user tapped "Continue"
  /// AND the OS permission was granted; `false` for "Not Now" or a denial.
  static Future<bool> show(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required Future<bool> Function() onContinue,
    List<String> bullets = const [],
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProminentDisclosureDialog(
        icon: icon,
        title: title,
        message: message,
        bullets: bullets,
        onContinue: onContinue,
      ),
    );
    return result ?? false;
  }

  @override
  State<ProminentDisclosureDialog> createState() =>
      _ProminentDisclosureDialogState();
}

class _ProminentDisclosureDialogState extends State<ProminentDisclosureDialog> {
  bool _requesting = false;

  Future<void> _handleContinue() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    // The OS runtime prompt is launched right here, in the same tap callback,
    // while this disclosure is still on screen.
    final granted = await widget.onContinue();
    if (mounted) Navigator.of(context).pop(granted);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF475569);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('prominent_disclosure_dialog'),
        backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icon, color: AppTheme.primaryBlue, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: textMain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.message,
                key: const Key('prominent_disclosure_message'),
                style: TextStyle(fontSize: 15, height: 1.45, color: textMain),
              ),
              if (widget.bullets.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final b in widget.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.check_circle,
                              size: 16, color: AppTheme.emeraldGreen),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            b,
                            style: TextStyle(
                                fontSize: 13.5, height: 1.4, color: textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        actions: [
          TextButton(
            key: const Key('prominent_disclosure_not_now'),
            onPressed:
                _requesting ? null : () => Navigator.of(context).pop(false),
            child: Text('Not Now', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            key: const Key('prominent_disclosure_continue'),
            onPressed: _requesting ? null : _handleContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

/// Runtime-permission entry points. Every OS permission prompt in the app goes
/// through one of these, so each is always immediately preceded by its own
/// in-app disclosure.
class PermissionDisclosures {
  PermissionDisclosures._();

  static const String foregroundLocationMessage =
      'Swift Ride collects your location data to display your current pickup '
      'point, calculate accurate routes and fares, and connect you with nearby '
      'drivers while using the app.';

  static const String driverLocationMessage =
      'Swift Ride collects your location data to show you nearby ride '
      'requests, share your live position with your rider during a trip, and '
      'calculate accurate arrival times while you are online and using the app.';

  static const String backgroundLocationMessage =
      'Swift Ride collects location data to enable real-time trip navigation, '
      'live driver tracking, and accurate arrival ETAs for riders even when the '
      'app is closed or not in use.';

  static const String notificationsMessage =
      'Swift Ride sends notifications for ride updates — such as when a '
      'driver accepts your request, arrives at pickup, or when a safety (SOS) '
      'alert is raised.';

  static bool _locationPromptInFlight = false;

  /// Ensures foreground ("while using the app") location permission.
  ///
  /// Returns `true` immediately if already granted. Otherwise shows the
  /// disclosure; only "Continue" invokes the OS prompt.
  static Future<bool> ensureForegroundLocation(
    BuildContext context, {
    bool asDriver = false,
  }) async {
    final loc = CustomChangeNotifierProvider.read<LocationProvider>(context);
    final status = await loc.permissionStatus();
    if (status == true) return true;
    // No native location platform (e.g. headless tests): nothing to prompt.
    if (status == null) return false;
    if (!context.mounted || _locationPromptInFlight) return false;

    _locationPromptInFlight = true;
    try {
      return await ProminentDisclosureDialog.show(
        context,
        icon: Icons.location_on_rounded,
        title: asDriver
            ? 'Location Needed to Go Online'
            : 'Allow Location Access',
        message: asDriver ? driverLocationMessage : foregroundLocationMessage,
        bullets: const [
          'Used only while you are using the app.',
          'Never sold or used for advertising.',
          'You can change this anytime in your device Settings.',
        ],
        onContinue: loc.requestPermission,
      );
    } finally {
      _locationPromptInFlight = false;
    }
  }

  /// Ensures background ("Allow all the time") location permission for drivers.
  ///
  /// Do NOT request background location on app launch. Only request it when a
  /// driver switches to Driver Mode or taps "Go Online".
  /// Shown immediately before calling `loc.requestBackgroundPermission()`.
  static Future<bool> ensureBackgroundLocation(BuildContext context) async {
    final loc = CustomChangeNotifierProvider.read<LocationProvider>(context);
    final status = await loc.backgroundPermissionStatus();
    if (status == true) return true;
    // No native platform (e.g. headless tests): nothing to prompt.
    if (status == null) return false;
    if (!context.mounted) return false;

    return ProminentDisclosureDialog.show(
      context,
      icon: Icons.location_on_rounded,
      title: 'Background Location Access',
      message: backgroundLocationMessage,
      bullets: const [
        'Enables live navigation and driver tracking while the screen is off or another app is open.',
        'Provides riders with accurate live arrival ETAs.',
        'Active only while you are online and working as a driver.',
      ],
      onContinue: loc.requestBackgroundPermission,
    );
  }

  static const String _notifAskedKey = 'notif_disclosure_shown_v1';

  /// Requests notification permission with its own disclosure. Deferred until
  /// after a ride is booked / the driver goes online so it never interrupts
  /// the location flow. Shown at most once; later enabling is via Settings.
  static Future<bool> ensureNotifications(BuildContext context) async {
    if (kIsWeb || Firebase.apps.isEmpty) return false;
    final messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        return true;
      }
    } catch (_) {}

    final storage = NativeStorageService();
    if (await storage.getBool(_notifAskedKey) == true) return false;
    if (!context.mounted) return false;
    await storage.setBool(_notifAskedKey, true);
    if (!context.mounted) return false;

    return ProminentDisclosureDialog.show(
      context,
      icon: Icons.notifications_active_rounded,
      title: 'Stay Updated on Your Ride',
      message: notificationsMessage,
      onContinue: () async {
        try {
          final s = await messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
          return s.authorizationStatus == AuthorizationStatus.authorized ||
              s.authorizationStatus == AuthorizationStatus.provisional;
        } catch (_) {
          return false;
        }
      },
    );
  }
}
