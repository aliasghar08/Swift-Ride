import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../view_models/responsive_layout_helper.dart';

enum AuthStep { phone, otp, profile }

/// Interactive Firebase Phone Authentication screen with OTP verification,
/// resend timer, profile onboarding, and quick test number autofill.
class PhoneAuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;

  const PhoneAuthScreen({super.key, this.onAuthSuccess});

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
  UserRole _selectedRole = UserRole.rider;

  Timer? _countdownTimer;
  int _secondsRemaining = 45;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
      if (auth.currentUser.phone.isNotEmpty) {
        final p = auth.currentUser.phone;
        if (p.startsWith('+92')) {
          _phoneController.text = p.substring(3);
        } else {
          _phoneController.text = p;
        }
      }
      if (auth.currentUser.fullName.isNotEmpty) {
        _nameController.text = auth.currentUser.fullName;
      }
      _selectedRole = auth.activeRole;
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onSuccessNavigate() {
    if (widget.onAuthSuccess != null) {
      widget.onAuthSuccess!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed('/');
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
    if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.startsWith('92')) {
      cleaned = cleaned.substring(2);
    }
    return '+92$cleaned';
  }

  void _useTestNumber() {
    _phoneController.text = '3000000000';
    _otpController.text = '123456';
    _nameController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Loaded test credentials (+92 300 0000000 / OTP: 123456)',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleSendOtp() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your mobile phone number',
          ),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    final fullPhone = _formatPhoneNumber(rawPhone);
    // E.164 verification: must be at least + followed by 9 digits
    if (fullPhone.length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid phone number (e.g. 300 1234567)',
          ),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);

    await auth.sendOtp(
      phoneNumber: fullPhone,
      onCodeSent: (vId, token) {
        setState(() {
          _currentStep = AuthStep.otp;
        });
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification code sent to $fullPhone'),
            backgroundColor: AppTheme.emeraldGreen,
          ),
        );
      },
      onError: (err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppTheme.sunsetCoral),
        );
      },
    );
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit OTP code'),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    final fullPhone = _formatPhoneNumber(_phoneController.text.trim());
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);

    await auth.verifyOtp(
      smsCode: code,
      phoneNumber: fullPhone,
      fullName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
      role: _selectedRole,
      onSuccess: () {
        _countdownTimer?.cancel();
        if (_nameController.text.trim().isNotEmpty) {
          _onSuccessNavigate();
        } else {
          setState(() {
            _currentStep = AuthStep.profile;
          });
        }
      },
      onError: (err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppTheme.sunsetCoral),
        );
      },
    );
  }

  Future<void> _handleSaveProfile() async {
    // Guard against double submission: this writes the user document and would
    // otherwise fire once per tap.
    if (_isSavingProfile) return;
    setState(() => _isSavingProfile = true);

    final name = _nameController.text.trim();
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);

    final resolvedName = name.isNotEmpty ? name : 'SwiftRide User';
    final updated = auth.currentUser.copyWith(
      fullName: resolvedName,
      role: _selectedRole,
    );
    auth.updateUser(updated);
    auth.switchRole(_selectedRole);
    try {
      await auth.firestoreUserService.saveUser(updated);
    } catch (e) {
      debugPrint('[PhoneAuthScreen] Save user warning: $e');
    }

    if (mounted) setState(() => _isSavingProfile = false);

    if (!mounted) return;
    _onSuccessNavigate();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SwiftRide Authentication'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep != AuthStep.phone
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    if (_currentStep == AuthStep.profile) {
                      _currentStep = AuthStep.otp;
                    } else {
                      _currentStep = AuthStep.phone;
                    }
                  });
                },
              )
            : IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: _onSuccessNavigate,
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: layout.scale(24),
            vertical: layout.scale(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Branding (Secret long-press to autofill test credentials for developers)
              Center(
                child: GestureDetector(
                  onTap: _useTestNumber,
                  onLongPress: _useTestNumber,
                  child: Container(
                    width: layout.scale(72),
                    height: layout.scale(72),
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: AppTheme.glowShadow(
                        AppTheme.primaryBlue,
                        blur: 20,
                      ),
                    ),
                    child: const Icon(
                      Icons.directions_car_filled,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _currentStep == AuthStep.phone
                    ? 'Enter Your Mobile Number'
                    : _currentStep == AuthStep.otp
                    ? 'Enter 6-Digit Code'
                    : 'Setup Your Profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: layout.fontSize(24),
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppTheme.darkNavy,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _currentStep == AuthStep.phone
                    ? 'We will send a 6-digit verification code.'
                    : _currentStep == AuthStep.otp
                    ? 'Sent to ${_formatPhoneNumber(_phoneController.text)}'
                    : 'Choose your account role and display name for Jhang & Toba Tek Singh.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: layout.fontSize(13),
                  color: AppTheme.slateMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Animated Step Container
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCurrentStepWidget(layout, auth, isDark),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
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
      case AuthStep.otp:
        return _buildOtpInputStep(layout, auth, isDark);
      case AuthStep.profile:
        return _buildProfileSetupStep(layout, auth, isDark);
    }
  }

  Widget _buildPhoneInputStep(
    ResponsiveLayoutHelper layout,
    AuthProvider auth,
    bool isDark,
  ) {
    final c = AppColors.of(layout.context);
    return Column(
      key: const ValueKey('phone_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
            boxShadow: AppTheme.subtleElevation,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('🇵🇰', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      '+92',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: layout.fontSize(15),
                        color: isDark ? Colors.white : AppTheme.darkNavy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  style: TextStyle(
                    fontSize: layout.fontSize(16),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                  decoration: const InputDecoration(
                    hintText: '300 1234567',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: auth.isLoading ? null : _handleSendOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
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
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: c.border.withValues(alpha: 0.5))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'OR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Expanded(child: Divider(color: c.border.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            final authProv = CustomChangeNotifierProvider.of<AuthProvider>(context);
            if (!authProv.isAuthenticated) {
              await authProv.authService.signInAnonymously();
            }
            if (!mounted) return;
            _onSuccessNavigate();
          },
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text(
            'Continue as AI Guest / Passenger',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? AppTheme.accentCyan : AppTheme.primaryNavy,
            side: BorderSide(
              color: isDark
                  ? AppTheme.accentCyan.withValues(alpha: 0.45)
                  : AppTheme.primaryNavy.withValues(alpha: 0.35),
              width: 1.3,
            ),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  final digit = index < otpText.length ? otpText[index] : '';
                  final isFocused = index == otpText.length ||
                      (index == 5 && otpText.length == 6);
                  final isFilled = digit.isNotEmpty;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: layout.scale(46),
                    height: layout.scale(54),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? (isFilled
                              ? AppTheme.accentCyan.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.05))
                          : (isFilled
                              ? AppTheme.primaryBlue.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.03)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFocused
                            ? (isDark ? AppTheme.accentCyan : AppTheme.primaryBlue)
                            : (isFilled
                                ? (isDark
                                    ? AppTheme.accentCyan.withValues(alpha: 0.55)
                                    : AppTheme.primaryBlue.withValues(alpha: 0.55))
                                : c.border),
                        width: isFocused ? 2.0 : 1.2,
                      ),
                      boxShadow: isFocused
                          ? AppTheme.glowShadow(
                              isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
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
                        color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                      ),
                    ),
                  );
                }),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _currentStep = AuthStep.phone;
                });
              },
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Edit Phone', style: TextStyle(fontSize: 13)),
            ),
            _canResend
                ? TextButton(
                    onPressed: _handleSendOtp,
                    child: const Text(
                      'Resend Code',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                : Text(
                    'Resend Code in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 13,
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
            color: isDark
                ? AppTheme.accentCyan.withValues(alpha: 0.1)
                : AppTheme.primaryBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? AppTheme.accentCyan.withValues(alpha: 0.2)
                  : AppTheme.primaryBlue.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Demo / Test Account? Enter code 123456 to verify.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : AppTheme.darkNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
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
          decoration: const InputDecoration(
            labelText: 'Full Name',
            hintText: 'e.g. Tariq Mehmood',
            prefixIcon: Icon(Icons.person),
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
                label: const Text('Rider (Book Rides)'),
                selected: _selectedRole == UserRole.rider,
                onSelected: (val) {
                  if (val) setState(() => _selectedRole = UserRole.rider);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Driver (Earn 100%)'),
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
              const Icon(Icons.location_on, size: 18, color: AppTheme.accentCyan),
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
        ElevatedButton(
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
