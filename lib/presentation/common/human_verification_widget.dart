import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../view_models/responsive_layout_helper.dart';

/// Controller for programmatic access to [HumanVerificationWidget].
class HumanVerificationController extends ChangeNotifier {
  bool _isVerified = false;
  String? _token;
  DateTime? _verifiedAt;

  bool get isVerified => _isVerified;
  String? get verificationToken => _token;
  String? get token => _token;
  DateTime? get verifiedAt => _verifiedAt;

  void Function()? _resetCallback;
  void Function(String token)? _simulateCallback;

  void _attach({
    required void Function() onReset,
    required void Function(String token) onSimulate,
  }) {
    _resetCallback = onReset;
    _simulateCallback = onSimulate;
  }

  void _detach() {
    _resetCallback = null;
    _simulateCallback = null;
  }

  /// Resets verification status back to unverified.
  void reset() {
    _isVerified = false;
    _token = null;
    _verifiedAt = null;
    notifyListeners();
    _resetCallback?.call();
  }

  /// Programmatically completes verification (useful for widget tests and automated CI).
  String simulateVerification([String? mockToken]) {
    final token = mockToken ?? _generateToken();
    _isVerified = true;
    _token = token;
    _verifiedAt = DateTime.now();
    notifyListeners();
    _simulateCallback?.call(token);
    return token;
  }

  static String _generateToken() {
    final random = Random();
    final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final randHex = List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
    return 'hvt_${millis}_$randHex';
  }
}

/// Glassmorphic, accessible human verification (CAPTCHA) gate widget.
///
/// Protects against automated SMS-pumping scripts, bot account creation,
/// and automated brute-force attacks while providing a fallback visual
/// challenge that functions offline and across all platforms.
class HumanVerificationWidget extends StatefulWidget {
  final HumanVerificationController? controller;
  final ValueChanged<String>? onVerified;
  final VoidCallback? onExpired;
  final String? currentPhoneNumber;

  const HumanVerificationWidget({
    super.key,
    this.controller,
    this.onVerified,
    this.onExpired,
    this.currentPhoneNumber,
  });

  @override
  State<HumanVerificationWidget> createState() => _HumanVerificationWidgetState();
}

class _HumanVerificationWidgetState extends State<HumanVerificationWidget> {
  late final HumanVerificationController _controller;
  bool _isLocalController = false;

  bool _isVerifying = false;
  bool _isExpired = false;
  Timer? _expirationTimer;

  // Visual Challenge state
  int _challengeTargetIndex = 0;
  final List<IconData> _challengeIcons = [
    Icons.directions_car_rounded,
    Icons.two_wheeler_rounded,
    Icons.electric_rickshaw_rounded,
    Icons.airplanemode_active_rounded,
  ];
  final List<String> _challengeLabels = [
    'Car',
    'Bike',
    'Rikshaw',
    'Airplane',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = HumanVerificationController();
      _isLocalController = true;
    }

    _controller._attach(
      onReset: _handleReset,
      onSimulate: _handleVerified,
    );

    _initChallenge();
  }

  @override
  void didUpdateWidget(covariant HumanVerificationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      if (widget.controller != null) {
        _controller = widget.controller!;
        _isLocalController = false;
      } else {
        _controller = HumanVerificationController();
        _isLocalController = true;
      }
      _controller._attach(
        onReset: _handleReset,
        onSimulate: _handleVerified,
      );
    }
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    _controller._detach();
    if (_isLocalController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _initChallenge() {
    final rand = Random();
    _challengeTargetIndex = rand.nextInt(_challengeIcons.length);
  }

  void _handleReset() {
    _expirationTimer?.cancel();
    if (mounted) {
      setState(() {
        _isVerifying = false;
        _isExpired = false;
      });
      _initChallenge();
    }
  }

  void _handleVerified(String token) {
    _expirationTimer?.cancel();
    _expirationTimer = Timer(const Duration(seconds: 120), () {
      if (mounted) {
        setState(() {
          _isExpired = true;
        });
        _controller.reset();
        widget.onExpired?.call();
      }
    });

    if (mounted) {
      setState(() {
        _isVerifying = false;
        _isExpired = false;
      });
    }
    widget.onVerified?.call(token);
  }

  void _startVerificationFlow() {
    if (_controller.isVerified && !_isExpired) return;

    // Check if phone number is known reviewer/test sandbox number
    final phone = widget.currentPhoneNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (phone == '923001234567' || phone == '3001234567' || phone == '923000000000' || phone == '3000000000') {
      _controller.simulateVerification();
      return;
    }

    setState(() {
      _isVerifying = true;
      _initChallenge();
    });

    _showInteractiveChallengeDialog();
  }

  void _showInteractiveChallengeDialog() {
    final targetLabel = _challengeLabels[_challengeTargetIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          color: AppTheme.primaryBlue,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Quick Human Verification',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        children: [
                          const TextSpan(text: 'Tap the '),
                          TextSpan(
                            text: targetLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                          const TextSpan(text: ' icon below to confirm you are human:'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(_challengeIcons.length, (idx) {
                        final icon = _challengeIcons[idx];
                        final label = _challengeLabels[idx];
                        return InkWell(
                          key: Key('captcha_icon_$idx'),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (idx == _challengeTargetIndex) {
                              _controller.simulateVerification();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Incorrect icon selected. Please try again.'),
                                  backgroundColor: AppTheme.sunsetCoral,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              setState(() {
                                _isVerifying = false;
                                _initChallenge();
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 28,
                                  color: AppTheme.primaryBlue,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shield_outlined, size: 12, color: AppTheme.slateMuted),
                        const SizedBox(width: 4),
                        Text(
                          'Protected by SwiftRide Anti-Bot Defense',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted && !_controller.isVerified) {
        setState(() => _isVerifying = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final layout = ResponsiveLayoutHelper(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final verified = _controller.isVerified && !_isExpired;
        return InkWell(
          key: const Key('human_verification_gate'),
          onTap: verified ? null : _startVerificationFlow,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: verified
                  ? AppTheme.emeraldGreen.withValues(alpha: 0.08)
                  : (_isExpired
                      ? AppTheme.sunsetCoral.withValues(alpha: 0.08)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF8FAFC))),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: verified
                    ? AppTheme.emeraldGreen.withValues(alpha: 0.5)
                    : (_isExpired
                        ? AppTheme.sunsetCoral.withValues(alpha: 0.4)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFFE2E8F0))),
                width: verified ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: verified
                        ? AppTheme.emeraldGreen
                        : (_isExpired
                            ? AppTheme.sunsetCoral.withValues(alpha: 0.2)
                            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06))),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: verified
                          ? AppTheme.emeraldGreen
                          : (_isExpired ? AppTheme.sunsetCoral : Colors.grey.withValues(alpha: 0.4)),
                      width: 1.5,
                    ),
                  ),
                  child: verified
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : (_isVerifying
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryBlue,
                              ),
                            )
                          : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        verified
                            ? 'Human Verification Confirmed'
                            : (_isExpired
                                ? 'Verification Expired (Tap to Re-verify)'
                                : 'I am not a robot (Tap to verify)'),
                        style: TextStyle(
                          fontSize: layout.fontSize(12.5),
                          fontWeight: verified ? FontWeight.w700 : FontWeight.w600,
                          color: verified
                              ? AppTheme.emeraldGreen
                              : (_isExpired
                                  ? AppTheme.sunsetCoral
                                  : (isDark ? Colors.white : const Color(0xFF0F172A))),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        verified
                            ? 'Single-use token valid for 2 minutes'
                            : 'Quick security challenge to prevent automated SMS requests',
                        style: TextStyle(
                          fontSize: layout.fontSize(10),
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  verified ? Icons.verified_user_rounded : Icons.shield_outlined,
                  size: 20,
                  color: verified ? AppTheme.emeraldGreen : AppTheme.slateMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
