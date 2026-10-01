import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
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
  final TextEditingController _nameController = TextEditingController();
  UserRole _selectedRole = UserRole.rider;

  Timer? _countdownTimer;
  int _secondsRemaining = 60;
  bool _canResend = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _secondsRemaining = 60;
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
    var cleaned = raw.replaceAll(RegExp(r'\D'), '');
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
    _nameController.text = 'Alex Morgan';
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Loaded test credentials (+92 300 0000000 / OTP: 123456)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleSendOtp() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty || rawPhone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Pakistani phone number (e.g. 300 1234567)'),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    final fullPhone = _formatPhoneNumber(rawPhone);
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
          SnackBar(
            content: Text(err),
            backgroundColor: AppTheme.sunsetCoral,
          ),
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

    final success = await auth.verifyOtp(
      smsCode: code,
      phoneNumber: fullPhone,
      fullName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : null,
      role: _selectedRole,
      onSuccess: () {
        _countdownTimer?.cancel();
        if (widget.onAuthSuccess != null) {
          widget.onAuthSuccess!();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      onError: (err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppTheme.sunsetCoral,
          ),
        );
      },
    );

    if (success && mounted && _nameController.text.trim().isEmpty) {
      // Prompt for name / onboarding if needed
      setState(() {
        _currentStep = AuthStep.profile;
      });
    }
  }

  Future<void> _handleSaveProfile() async {
    final name = _nameController.text.trim();
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);

    if (name.isNotEmpty) {
      final updated = auth.currentUser.copyWith(
        fullName: name,
        role: _selectedRole,
      );
      auth.updateUser(updated);
      auth.switchRole(_selectedRole);
      await auth.firestoreUserService.saveUser(updated);
    }

    if (!mounted) return;
    if (widget.onAuthSuccess != null) {
      widget.onAuthSuccess!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
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
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
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
              // Header & Branding
              Center(
                child: Container(
                  width: layout.scale(72),
                  height: layout.scale(72),
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.glowShadow(AppTheme.primaryBlue, blur: 20),
                  ),
                  child: const Icon(Icons.directions_car_filled, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _currentStep == AuthStep.phone
                    ? 'Enter Phone Number'
                    : _currentStep == AuthStep.otp
                        ? 'Verify OTP Code'
                        : 'Complete Your Profile',
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
                    ? 'We will send a 6-digit verification code to authenticate your account with 0% platform commission.'
                    : _currentStep == AuthStep.otp
                        ? 'Enter the 6-digit code sent to ${_formatPhoneNumber(_phoneController.text)}'
                        : 'Choose your account type and display name.',
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

              // Test Environment Helper
              if (_currentStep == AuthStep.phone) ...[
                const Divider(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _useTestNumber,
                  icon: const Icon(Icons.flash_on, color: AppTheme.amberWarning),
                  label: const Text(
                    'Fill Demo / Test Number (+92 300 0000000)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : AppTheme.darkNavy,
                    side: BorderSide(
                      color: AppTheme.amberWarning.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '💡 Firebase Phone Auth test bypass enabled for instant login.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: layout.fontSize(11),
                    color: AppTheme.slateMuted,
                  ),
                ),
              ],
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
    return Column(
      key: const ValueKey('phone_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            boxShadow: AppTheme.subtleElevation,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: auth.isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Send OTP Code',
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
      ],
    );
  }

  Widget _buildOtpInputStep(
    ResponsiveLayoutHelper layout,
    AuthProvider auth,
    bool isDark,
  ) {
    return Column(
      key: const ValueKey('otp_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            boxShadow: AppTheme.subtleElevation,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: TextStyle(
              fontSize: layout.fontSize(24),
              fontWeight: FontWeight.w800,
              letterSpacing: 12,
              color: isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
            ),
            decoration: const InputDecoration(
              hintText: '••••••',
              hintStyle: TextStyle(letterSpacing: 8),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
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
                    child: const Text('Resend Code', style: TextStyle(fontWeight: FontWeight.w700)),
                  )
                : Text(
                    'Resend code in ${_secondsRemaining}s',
                    style: TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                  ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: auth.isLoading ? null : _handleVerifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.emeraldGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: auth.isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  'Verify & Continue',
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
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _handleSaveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
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
