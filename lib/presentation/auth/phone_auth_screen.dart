import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show PhoneAuthCredential;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/phone_number_formatter.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../common/google_logo.dart';
import '../common/legal_terms_modal.dart';
import '../common/reserved_bottom_ad_bar.dart';
import '../view_models/responsive_layout_helper.dart';

enum AuthStep { phone, autoVerifying, otp, profile }

/// Interactive Firebase Phone Authentication screen with OTP verification,
/// resend timer, profile onboarding, and quick test number autofill.
class PhoneAuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;

  const PhoneAuthScreen({super.key, this.onAuthSuccess});

  /// Smoothly navigates to [PhoneAuthScreen] using `Navigator.pushReplacement`
  /// (by default when switching sessions) or `Navigator.push`.
  static Future<T?> navigate<T>(
    BuildContext context, {
    bool replace = true,
    VoidCallback? onAuthSuccess,
  }) {
    final route = AppRouter.smoothRoute<T>(
      PhoneAuthScreen(onAuthSuccess: onAuthSuccess),
      settings: const RouteSettings(name: '/login'),
    );
    if (replace) {
      return Navigator.of(context).pushReplacement<T, Object?>(route);
    }
    return Navigator.of(context).push<T>(route);
  }

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  AuthStep _currentStep = AuthStep.phone;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  bool _isSavingProfile = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  UserRole _selectedRole = UserRole.passenger;

  String? _lastLookedUpPhone;
  bool _isProfileAutofilled = false;
  bool _suppressAutoLookup = false;
  String? _inlineError;

  Timer? _countdownTimer;
  Timer? _autoVerifyTimer;
  int _secondsRemaining = 45;
  bool _canResend = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool get _isSocialLoading => _isGoogleLoading || _isAppleLoading;

  /// Sign in with Apple is only offered on Apple platforms (iOS / macOS).
  bool get _showAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _inlineError = message;
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.sunsetCoral,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _clearInlineError() {
    if (_inlineError != null && mounted) {
      setState(() {
        _inlineError = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_handlePhoneInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);
      if (auth.currentUser.phone.isNotEmpty) {
        final p = auth.currentUser.phone;
        if (p.startsWith('+92')) {
          _phoneController.text = p.substring(3);
        } else {
          _phoneController.text = p;
        }
      }
      if (auth.currentUser.fullName.isNotEmpty &&
          auth.currentUser.fullName != 'Guest User') {
        _nameController.text = auth.currentUser.fullName;
      }
      if (auth.currentUser.email != null &&
          auth.currentUser.email!.isNotEmpty) {
        _emailController.text = auth.currentUser.email!;
      }
      _selectedRole = auth.activeRole;
      if (_phoneController.text.trim().isNotEmpty) {
        _handlePhoneInputChanged();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoVerifyTimer?.cancel();
    _phoneController.removeListener(_handlePhoneInputChanged);
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handlePhoneInputChanged() async {
    if (!mounted || _suppressAutoLookup) return;
    final raw = _phoneController.text.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      if (_lastLookedUpPhone != null || _isProfileAutofilled) {
        setState(() {
          if (digits.length < 7) {
            _isProfileAutofilled = false;
          }
          _lastLookedUpPhone = null;
        });
      }
      return;
    }

    final fullPhone = _formatPhoneNumber(raw);
    if (_lastLookedUpPhone == fullPhone) return;
    _lastLookedUpPhone = fullPhone;

    try {
      final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);
      final matchedUser = await auth.lookupUserByPhone(fullPhone);
      if (!mounted || _suppressAutoLookup) return;
      if (matchedUser != null) {
        setState(() {
          if (matchedUser.fullName.isNotEmpty &&
              matchedUser.fullName != 'Guest User') {
            _nameController.text = matchedUser.fullName;
          }
          _emailController.text = matchedUser.email ?? '';
          _selectedRole = matchedUser.role;
          _isProfileAutofilled = true;
          _inlineError = null;
        });
      }
    } catch (_) {}
  }

  void _onSuccessNavigate() {
    if (widget.onAuthSuccess != null) {
      widget.onAuthSuccess!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      try {
        Navigator.of(context).pushReplacementNamed('/');
      } catch (_) {}
    }
  }

  Widget _buildGoogleIcon() {
    return const GoogleLogo(size: 20);
  }

  Future<void> _handleGoogleSignIn() async {
    _clearInlineError();
    setState(() => _isGoogleLoading = true);
    final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);
    try {
      await auth.signInWithGoogle(
        selectedRole: _selectedRole.name,
        fullName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : null,
        onSuccess: () {
          if (!mounted) return;
          _onSuccessNavigate();
        },
        onError: (err) {
          if (!mounted) return;
          _setError(err);
        },
      );
    } catch (e) {
      if (mounted) {
        _setError(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    _clearInlineError();
    setState(() => _isAppleLoading = true);
    final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);
    try {
      await auth.signInWithApple(
        selectedRole: _selectedRole.name,
        fullName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : null,
        onSuccess: () {
          if (!mounted) return;
          _onSuccessNavigate();
        },
        onError: (err) {
          if (!mounted) return;
          _setError(err);
        },
      );
    } catch (e) {
      if (mounted) {
        _setError(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isAppleLoading = false);
      }
    }
  }

  void _startResendTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _secondsRemaining = 45;
      _canResend = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        setState(() {
          _canResend = true;
          _secondsRemaining = 0;
        });
      }
    });
  }

  String _formatPhoneNumber(String raw) {
    var trimmed = raw.trim();
    if (trimmed.startsWith('+')) {
      return '+${trimmed.replaceAll(RegExp(r'\D'), '')}';
    }
    var cleaned = trimmed.replaceAll(RegExp(r'\D'), '');
    if (cleaned.startsWith('00')) {
      return '+${cleaned.substring(2)}';
    }
    // Support US Reviewer Demo numbers (+1 555-010-0001 / +1 555-010-0002)
    if (cleaned == '15550100001' || cleaned == '15550100002') {
      return '+$cleaned';
    }
    if (cleaned == '5550100001' || cleaned == '5550100002') {
      return '+1$cleaned';
    }
    cleaned = PhoneNumberFormatter.clean(cleaned);
    return '+92$cleaned';
  }

  void _useTestNumber() {
    if (kReleaseMode) return;
    _suppressAutoLookup = true;
    _phoneController.text = '3000000000';
    _otpController.text = '123456';
    _nameController.clear();
    _emailController.clear();
    _isProfileAutofilled = false;
    _clearInlineError();
  }

  Future<void> _handleSendOtp() async {
    _clearInlineError();
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      _setError('Please enter your mobile phone number (e.g. 300 1234567).');
      return;
    }

    final fullPhone = _formatPhoneNumber(rawPhone);
    final rawDigits = fullPhone.replaceAll(RegExp(r'\D'), '');
    // E.164 verification: must be at least + followed by 11+ total digits (e.g. +92 + 10 digits or +1 + 10 digits)
    if (fullPhone.length < 12 || rawDigits.length < 11) {
      _setError(
        'Please enter a valid 10-digit mobile number (e.g. 300 1234567).',
      );
      return;
    }

    final enteredName = _nameController.text.trim();
    if (enteredName.isNotEmpty && enteredName.length < 2) {
      _setError('Please enter a valid full name (at least 2 characters).');
      return;
    }

    final enteredEmail = _emailController.text.trim();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (enteredEmail.isNotEmpty && !emailRegex.hasMatch(enteredEmail)) {
      _setError(
        'Please enter a valid email address (e.g. name@example.com) or leave it blank.',
      );
      return;
    }

    final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);

    // Pre-fetch profile by phone if user hasn't filled name yet and auto-lookup wasn't suppressed
    if (!_suppressAutoLookup && _nameController.text.trim().isEmpty) {
      try {
        final matched = await auth.lookupUserByPhone(fullPhone);
        if (matched != null && mounted) {
          setState(() {
            if (_nameController.text.trim().isEmpty &&
                matched.fullName.isNotEmpty &&
                matched.fullName != 'Guest User') {
              _nameController.text = matched.fullName;
            }
            if (_emailController.text.trim().isEmpty &&
                matched.email != null &&
                matched.email!.isNotEmpty) {
              _emailController.text = matched.email!;
            }
            _selectedRole = matched.role;
            _isProfileAutofilled = true;
          });
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _currentStep = AuthStep.autoVerifying;
      _inlineError = null;
    });

    _autoVerifyTimer?.cancel();
    bool autoVerified = false;

    await auth.sendOtp(
      phoneNumber: fullPhone,
      onAutoVerified: (PhoneAuthCredential credential) async {
        autoVerified = true;
        _autoVerifyTimer?.cancel();
        if (!mounted) return;

        try {
          await auth.signInWithCredential(
            credential,
            phoneNumber: fullPhone,
            fullName: _nameController.text.trim().isNotEmpty
                ? _nameController.text.trim()
                : null,
            email: _emailController.text.trim().isNotEmpty
                ? _emailController.text.trim()
                : null,
            role: _selectedRole,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.verified_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Phone verified automatically! Signing in...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          _onSuccessNavigate();
        } catch (e) {
          if (mounted) {
            setState(() {
              _currentStep = AuthStep.otp;
            });
            _startResendTimer();
            _setError('Auto-sign in error: $e');
          }
        }
      },
      onCodeSent: (vId, token) {
        if (!mounted || autoVerified) return;
        _autoVerifyTimer?.cancel();

        // If an SMS code was already auto-detected (not via manual dev test button),
        // verify and sign in immediately without showing the OTP input screen.
        final preDetectedCode = _otpController.text
            .replaceAll(RegExp(r'\D'), '')
            .trim();
        if (!_suppressAutoLookup && preDetectedCode.length == 6) {
          _handleVerifyOtp();
          return;
        }

        if (fullPhone != '+923000000000') {
          _otpController.clear();
        }
        setState(() {
          _currentStep = AuthStep.otp;
          _inlineError = null;
        });
        _startResendTimer();
        ScaffoldMessenger.of(context).clearSnackBars();

        final isSimOrDemo =
            !kReleaseMode &&
            (vId.startsWith('sim_otp_') ||
                vId.startsWith('reviewer_demo_') ||
                fullPhone == '+923000000000');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.mark_email_read_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isSimOrDemo
                        ? 'Verification code sent to $fullPhone (Emulator code: 123456).'
                        : '6-digit verification code sent via SMS to $fullPhone.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      },
      onAutoRetrievalTimeout: (vId) {
        if (!mounted || autoVerified) return;
        _autoVerifyTimer?.cancel();
        if (_currentStep != AuthStep.otp && _currentStep != AuthStep.profile) {
          setState(() {
            _currentStep = AuthStep.otp;
          });
          _startResendTimer();
        }
      },
      onError: (err) {
        _autoVerifyTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _currentStep = AuthStep.phone;
        });
        String friendlyError = err;
        if (err.contains('invalid-phone-number')) {
          friendlyError = 'Invalid phone number format. Please enter a valid 10-digit number (e.g. 300 1234567).';
        } else if (err.contains('39') ||
            err.contains('17499') ||
            err.contains('Error code:39') ||
            err.contains('internal error has occurred')) {
          friendlyError = AuthService.smsUnavailableMessage;
        } else if (err.contains('too-many-requests')) {
          friendlyError = 'Too many requests. Please wait a minute before requesting a new code.';
        } else if (err.contains('quota-exceeded')) {
          friendlyError =
              'Daily SMS verification quota reached. Please try again later.';
        } else if (err.contains('network-request-failed')) {
          friendlyError = 'Network connection problem. Please check your internet connection.';
        }
        _setError(friendlyError);
      },
    );
  }

  Future<void> _handleVerifyOtp() async {
    _clearInlineError();
    final rawCode = _otpController.text;
    final code = rawCode.replaceAll(RegExp(r'\D'), '').trim();
    if (code.length < 6) {
      _setError('Please enter the complete 6-digit OTP code received via SMS.');
      return;
    }

    final fullPhone = _formatPhoneNumber(_phoneController.text.trim());
    final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);
    _countdownTimer?.cancel();

    await auth.verifyOtp(
      smsCode: code,
      phoneNumber: fullPhone,
      fullName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
      email: _emailController.text.trim().isNotEmpty
          ? _emailController.text.trim()
          : null,
      role: _selectedRole,
      onSuccess: () {
        _countdownTimer?.cancel();
        if (_nameController.text.trim().isNotEmpty) {
          _onSuccessNavigate();
        } else {
          setState(() {
            _currentStep = AuthStep.profile;
            _inlineError = null;
          });
        }
      },
      onError: (err) {
        String friendlyError = err;
        if (err.contains('invalid-verification-code') ||
            err.toLowerCase().contains('invalid verification code') ||
            err.toLowerCase().contains('incorrect')) {
          friendlyError = 'Incorrect 6-digit verification code. Please check your SMS and try again.';
        } else if (err.contains('session-expired')) {
          friendlyError = 'The verification code has expired. Please tap "Resend Code" to receive a fresh SMS.';
        }
        _setError(friendlyError);
      },
    );
  }

  Future<void> _handleSaveProfile() async {
    if (_isSavingProfile) return;
    _clearInlineError();

    final name = _nameController.text.trim();
    if (name.isNotEmpty && name.length < 2) {
      _setError('Please enter a valid full name (at least 2 characters).');
      return;
    }

    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (email.isNotEmpty && !emailRegex.hasMatch(email)) {
      _setError(
        'Please enter a valid email address (e.g. name@example.com) or leave it blank.',
      );
      return;
    }

    setState(() => _isSavingProfile = true);

    final fullPhone = _formatPhoneNumber(_phoneController.text.trim());
    final auth = CustomChangeNotifierProvider.read<AuthProvider>(context);

    final resolvedName = name.isNotEmpty ? name : 'SwiftRide User';
    await auth.updateUserProfile(
      fullName: resolvedName,
      phone: fullPhone.length >= 11 ? fullPhone : auth.currentUser.phone,
      email: email,
      role: _selectedRole,
    );

    if (mounted) setState(() => _isSavingProfile = false);

    if (!mounted) return;
    _onSuccessNavigate();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final canCloseToActiveSession =
        auth.currentUser.phone.isNotEmpty || widget.onAuthSuccess != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SwiftRide Authentication'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _currentStep != AuthStep.phone
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _autoVerifyTimer?.cancel();
                  setState(() {
                    if (_currentStep == AuthStep.profile) {
                      _currentStep = AuthStep.otp;
                    } else {
                      _currentStep = AuthStep.phone;
                    }
                  });
                },
              )
            : (canCloseToActiveSession
                  ? IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: _onSuccessNavigate,
                    )
                  : null),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: layout.scale(24),
            vertical: layout.scale(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Branding
              Center(
                child: GestureDetector(
                  onLongPress: kReleaseMode ? null : _useTestNumber,
                  child: Container(
                    width: layout.scale(56),
                    height: layout.scale(56),
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: AppTheme.glowShadow(
                        AppTheme.primaryBlue,
                        blur: 16,
                      ),
                    ),
                    child: const Icon(
                      Icons.directions_car_filled,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _currentStep == AuthStep.phone
                    ? 'Enter Your Mobile Number'
                    : _currentStep == AuthStep.autoVerifying
                    ? 'Verifying Number...'
                    : _currentStep == AuthStep.otp
                    ? 'Enter 6-Digit Code'
                    : 'Setup Your Profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: layout.fontSize(22),
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppTheme.darkNavy,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _currentStep == AuthStep.phone
                    ? 'We will send a 6-digit verification code.'
                    : _currentStep == AuthStep.autoVerifying
                    ? 'Checking automatic verification. Please wait a moment...'
                    : _currentStep == AuthStep.otp
                    ? 'Sent to ${_formatPhoneNumber(_phoneController.text)}'
                    : 'Choose your account role and display name for Jhang & Toba Tek Singh.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: layout.fontSize(12.5),
                  color: AppTheme.slateMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),

              // Animated Step Container
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCurrentStepWidget(layout, auth, isDark),
              ),

              const SizedBox(height: 12),

              // Legal / Terms & Privacy Policy Footer (Required by App Store Guideline 5.1.1)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'By continuing, you agree to our ',
                      style: TextStyle(
                        fontSize: layout.fontSize(11.5),
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => LegalTermsModal.showTerms(context),
                      child: Text(
                        'Terms of Service',
                        style: TextStyle(
                          fontSize: layout.fontSize(11.5),
                          color: isDark
                              ? AppTheme.accentCyan
                              : AppTheme.primaryBlue,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      ' and ',
                      style: TextStyle(
                        fontSize: layout.fontSize(11.5),
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => LegalTermsModal.showPrivacy(context),
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: layout.fontSize(11.5),
                          color: isDark
                              ? AppTheme.accentCyan
                              : AppTheme.primaryBlue,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const ReservedBottomAdBar(),
    );
  }

  Widget _buildCurrentStepWidget(
    ResponsiveLayoutHelper layout,
    AuthProvider auth,
    bool isDark,
  ) {
    switch (_currentStep) {
      case AuthStep.phone:
        return _buildPhoneInputStep(layout, auth, isDark);
      case AuthStep.autoVerifying:
        return _buildAutoVerifyingStep(layout, auth, isDark);
      case AuthStep.otp:
        return _buildOtpInputStep(layout, auth, isDark);
      case AuthStep.profile:
        return _buildProfileSetupStep(layout, auth, isDark);
    }
  }

  Widget _buildAutoVerifyingStep(
    ResponsiveLayoutHelper layout,
    AuthProvider auth,
    bool isDark,
  ) {
    final c = AppColors.of(layout.context);
    final phone = _formatPhoneNumber(_phoneController.text);

    return Column(
      key: const ValueKey('auto_verifying_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.all(layout.scale(24)),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(layout.scale(16)),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: layout.scale(64),
                height: layout.scale(64),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox(
                    width: layout.scale(32),
                    height: layout.scale(32),
                    child: const CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: layout.scale(20)),
              Text(
                'Detecting Automatic Verification',
                style: TextStyle(
                  fontSize: layout.fontSize(18),
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: layout.scale(8)),
              Text(
                'Checking SMS detection for $phone.\nIf auto-verify succeeds, you will be signed in instantly without typing a code.',
                style: TextStyle(
                  fontSize: layout.fontSize(13),
                  color: c.textMuted,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: layout.scale(24)),
              OutlinedButton.icon(
                onPressed: () {
                  _autoVerifyTimer?.cancel();
                  setState(() {
                    _currentStep = AuthStep.otp;
                  });
                  _startResendTimer();
                },
                icon: const Icon(Icons.dialpad_rounded, size: 18),
                label: const Text('Enter Code Manually'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                  side: const BorderSide(color: AppTheme.primaryBlue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(layout.scale(10)),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: layout.scale(16),
                    vertical: layout.scale(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInlineErrorBanner(ResponsiveLayoutHelper layout, bool isDark) {
    final err = _inlineError;
    if (err == null || err.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('auth_error_banner'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.sunsetCoral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.sunsetCoral.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.sunsetCoral,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              err,
              style: TextStyle(
                fontSize: layout.fontSize(11.5),
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.darkNavy,
              ),
            ),
          ),
          InkWell(
            onTap: _clearInlineError,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppTheme.sunsetCoral,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneInputStep(
    ResponsiveLayoutHelper layout,
    AuthProvider auth,
    bool isDark,
  ) {
    final c = AppColors.of(layout.context);
    return AutofillGroup(
      key: const ValueKey('phone_step'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.currentUser.phone.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.emeraldGreen,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Session: ${auth.currentUser.phone}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: layout.fontSize(12),
                            color: isDark ? Colors.white : AppTheme.darkNavy,
                          ),
                        ),
                        Text(
                          'Logged in as ${auth.currentUser.fullName.isEmpty ? "SwiftRide User" : auth.currentUser.fullName}',
                          style: TextStyle(
                            fontSize: layout.fontSize(11),
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('active_session_sign_out_btn'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.sunsetCoral,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      await auth.signOut();
                      if (!mounted) return;
                      setState(() {
                        _phoneController.clear();
                        _nameController.clear();
                        _emailController.clear();
                        _isProfileAutofilled = false;
                        _lastLookedUpPhone = null;
                        _inlineError = null;
                      });
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Signed out successfully.'),
                          backgroundColor: AppTheme.emeraldGreen,
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    key: const Key('active_session_continue_btn'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _onSuccessNavigate,
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 1. Phone Number Input (Kept as first TextField for test & autofill priority)
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
              boxShadow: AppTheme.subtleElevation,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text('🇵🇰', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 5),
                      Text(
                        '+92',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: layout.fontSize(14),
                          color: isDark ? Colors.white : AppTheme.darkNavy,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('auth_phone_field'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    onChanged: (_) {
                      _suppressAutoLookup = false;
                      _clearInlineError();
                      _handlePhoneInputChanged();
                    },
                    inputFormatters: [
                      const PhoneNumberFormatter(),
                    ],
                    style: TextStyle(
                      fontSize: layout.fontSize(15),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                    decoration: InputDecoration(
                      hintText: '300 1234567',
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: _phoneController.text.isNotEmpty
                          ? IconButton(
                              key: const Key('clear_phone_btn'),
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              tooltip: 'Clear phone number',
                              onPressed: () {
                                setState(() {
                                  _phoneController.clear();
                                  _isProfileAutofilled = false;
                                  _lastLookedUpPhone = null;
                                  _inlineError = null;
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isProfileAutofilled) ...[
            const SizedBox(height: 6),
            Container(
              key: const Key('autofill_success_banner'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_fix_high_rounded,
                    size: 15,
                    color: AppTheme.emeraldGreen,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Profile fetched from phone & autofilled — you can edit below.',
                      style: TextStyle(
                        fontSize: layout.fontSize(11),
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppTheme.darkNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // 2. Full Name in its own separate row
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
              boxShadow: AppTheme.subtleElevation,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: TextField(
              key: const Key('auth_name_field'),
              controller: _nameController,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              onChanged: (_) => _clearInlineError(),
              style: TextStyle(
                fontSize: layout.fontSize(14),
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'Enter your full name',
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                prefixIcon: Icon(Icons.person_outline, size: 20),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 34,
                  minHeight: 36,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 3. Optional Email in its own separate row
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
              boxShadow: AppTheme.subtleElevation,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: TextField(
              key: const Key('auth_email_field'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) => _clearInlineError(),
              style: TextStyle(
                fontSize: layout.fontSize(14),
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                labelText: 'Email (Optional)',
                hintText: 'you@example.com',
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                prefixIcon: Icon(Icons.alternate_email, size: 19),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 34,
                  minHeight: 36,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 4. Account Role Selector in its own separate row
          Row(
            children: [
              Text(
                'Role:',
                style: TextStyle(
                  fontSize: layout.fontSize(12.5),
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Passenger'),
                  ),
                  selected: _selectedRole == UserRole.passenger,
                  onSelected: (val) {
                    if (val) setState(() => _selectedRole = UserRole.passenger);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Driver'),
                  ),
                  selected: _selectedRole == UserRole.driver,
                  onSelected: (val) {
                    if (val) setState(() => _selectedRole = UserRole.driver);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInlineErrorBanner(layout, isDark),
          ElevatedButton(
            key: const Key('continue_with_phone_btn'),
            onPressed: auth.isLoading ? null : _handleSendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: auth.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue with Phone',
                        style: TextStyle(
                          fontSize: layout.fontSize(15),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
          const SizedBox(height: 18),

          // OR divider
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: isDark ? Colors.white24 : Colors.black12,
                  thickness: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'OR',
                  style: TextStyle(
                    fontSize: layout.fontSize(12),
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : AppTheme.slateMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: isDark ? Colors.white24 : Colors.black12,
                  thickness: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Continue with Google Button
          OutlinedButton(
            key: const Key('continue_with_google_btn'),
            onPressed: (_isSocialLoading || auth.isLoading)
                ? null
                : _handleGoogleSignIn,
            style: OutlinedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF131314) : Colors.white,
              foregroundColor: isDark
                  ? const Color(0xFFE3E3E3)
                  : const Color(0xFF1F1F1F),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF444746)
                    : const Color(0xFFDADCE0),
                width: 1.0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isGoogleLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.white : AppTheme.primaryBlue,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildGoogleIcon(),
                      const SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: layout.fontSize(14.5),
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFFE3E3E3)
                              : const Color(0xFF1F1F1F),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
          ),
          // Continue with Apple Button — Apple platforms only (iOS / macOS).
          // Sign in with Apple is irrelevant on Android, so it is hidden there.
          if (_showAppleSignIn) ...[
            const SizedBox(height: 10),
            ElevatedButton(
              key: const Key('continue_with_apple_btn'),
              onPressed: (_isSocialLoading || auth.isLoading)
                  ? null
                  : _handleAppleSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF0F172A)
                    : Colors.black,
                foregroundColor: Colors.white,
                side: isDark ? const BorderSide(color: Colors.white24) : null,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isAppleLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.apple, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Continue with Apple',
                          style: TextStyle(
                            fontSize: layout.fontSize(14.5),
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtpInputStep(
    ResponsiveLayoutHelper layout,
    AuthProvider auth,
    bool isDark,
  ) {
    final c = AppColors.of(layout.context);
    final otpText = _otpController.text;

    return Column(
      key: const ValueKey('otp_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 6-digit OTP code tiles
        GestureDetector(
          onTap: () {
            _otpFocusNode.requestFocus();
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final digit = index < otpText.length ? otpText[index] : '';
                    final isFocused =
                        index == otpText.length ||
                        (index == 5 && otpText.length == 6);
                    final isFilled = digit.isNotEmpty;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: layout.scale(46),
                        height: layout.scale(54),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark
                              ? (isFilled
                                    ? AppTheme.accentCyan.withValues(
                                        alpha: 0.12,
                                      )
                                    : Colors.white.withValues(alpha: 0.05))
                              : (isFilled
                                    ? AppTheme.primaryBlue.withValues(
                                        alpha: 0.08,
                                      )
                                    : Colors.black.withValues(alpha: 0.03)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFocused
                                ? (isDark
                                      ? AppTheme.accentCyan
                                      : AppTheme.primaryBlue)
                                : (isFilled
                                      ? (isDark
                                            ? AppTheme.accentCyan.withValues(
                                                alpha: 0.55,
                                              )
                                            : AppTheme.primaryBlue.withValues(
                                                alpha: 0.55,
                                              ))
                                      : c.border),
                            width: isFocused ? 2.0 : 1.2,
                          ),
                          boxShadow: isFocused
                              ? AppTheme.glowShadow(
                                  isDark
                                      ? AppTheme.accentCyan
                                      : AppTheme.primaryBlue,
                                  blur: 8,
                                  opacity: 0.25,
                                )
                              : null,
                        ),
                        child: Text(
                          digit,
                          style: TextStyle(
                            fontSize: layout.fontSize(22),
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppTheme.accentCyan
                                : AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Underlying transparent text field capturing autofill and keyboard events
              Opacity(
                opacity: 0.0,
                child: TextField(
                  controller: _otpController,
                  focusNode: _otpFocusNode,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onChanged: (val) {
                    _clearInlineError();
                    setState(() {});
                    if (val.trim().length == 6 && !auth.isLoading) {
                      _handleVerifyOtp();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _currentStep = AuthStep.phone;
                  _inlineError = null;
                });
              },
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Edit Phone', style: TextStyle(fontSize: 12.5)),
            ),
            TextButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final text = data?.text ?? '';
                final digits = text.replaceAll(RegExp(r'\D'), '');
                if (digits.length >= 6) {
                  final code = digits.substring(0, 6);
                  setState(() {
                    _otpController.text = code;
                    _inlineError = null;
                  });
                  _handleVerifyOtp();
                } else {
                  _setError('No 6-digit verification code found in clipboard.');
                }
              },
              icon: const Icon(Icons.paste_rounded, size: 14),
              label: const Text('Paste Code', style: TextStyle(fontSize: 12.5)),
            ),
            _canResend
                ? TextButton(
                    onPressed: _handleSendOtp,
                    child: const Text(
                      'Resend Code',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  )
                : Text(
                    'Resend Code in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateMuted,
                    ),
                  ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132035) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.accentCyan.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 16,
                color: AppTheme.accentCyan,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Security Reminder: Never share your SwiftRide verification code with anyone.',
                  style: TextStyle(
                    fontSize: layout.fontSize(10.5),
                    color: c.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildInlineErrorBanner(layout, isDark),
        ElevatedButton(
          key: const Key('verify_and_login_btn'),
          onPressed: auth.isLoading ? null : _handleVerifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.emeraldGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: auth.isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Verify & Login',
                  style: TextStyle(
                    fontSize: layout.fontSize(15),
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildProfileSetupStep(
    ResponsiveLayoutHelper layout,
    AuthProvider auth,
    bool isDark,
  ) {
    return Column(
      key: const ValueKey('profile_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          onChanged: (_) => _clearInlineError(),
          decoration: const InputDecoration(
            labelText: 'Full Name',
            hintText: 'e.g. Tariq Mehmood',
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => _clearInlineError(),
          decoration: const InputDecoration(
            labelText: 'Email (Optional)',
            hintText: 'e.g. tariq@example.com',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Select Account Role',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: layout.fontSize(14),
            color: isDark ? Colors.white : AppTheme.darkNavy,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Passenger'),
                ),
                selected: _selectedRole == UserRole.passenger,
                onSelected: (val) {
                  if (val) setState(() => _selectedRole = UserRole.passenger);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Driver'),
                ),
                selected: _selectedRole == UserRole.driver,
                onSelected: (val) {
                  if (val) setState(() => _selectedRole = UserRole.driver);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.accentCyan.withValues(alpha: 0.08)
                : AppTheme.primaryBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? AppTheme.accentCyan.withValues(alpha: 0.25)
                  : AppTheme.primaryBlue.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 18,
                color: AppTheme.accentCyan,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Region: Jhang (31.2785, 72.3317) · AI Bidding Ready',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppTheme.darkNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildInlineErrorBanner(layout, isDark),
        ElevatedButton(
          key: const Key('complete_setup_btn'),
          onPressed: _isSavingProfile ? null : _handleSaveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSavingProfile
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Complete Setup',
                  style: TextStyle(
                    fontSize: layout.fontSize(15),
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }
}
