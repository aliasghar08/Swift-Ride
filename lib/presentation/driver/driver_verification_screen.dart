import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/driver_document_model.dart';
import '../../domain/models/vehicle_info_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../services/referral_link_service.dart';
import '../common/ai_consent_dialog.dart';
import '../common/reserved_bottom_ad_bar.dart';
import '../view_models/responsive_layout_helper.dart';

/// Screen allowing drivers to input vehicle legal and visual specifications,
/// upload official documents (CNIC, Driving License, Vehicle Registration),
/// and submit visual inspection photos (Front with plate, Interior cabin)
/// for real-time AI verification via Google Gemini 3.8 Flash.
class DriverVerificationScreen extends StatefulWidget {
  const DriverVerificationScreen({super.key});

  @override
  State<DriverVerificationScreen> createState() =>
      _DriverVerificationScreenState();
}

class _DriverVerificationScreenState extends State<DriverVerificationScreen> {
  final ImagePicker _picker = ImagePicker();
  final Map<DriverDocumentType, XFile?> _selectedFiles = {};
  final Map<DriverDocumentType, bool> _isVerifyingType = {};
  bool _initialized = false;

  late final TextEditingController _makeController;
  late final TextEditingController _modelController;
  late final TextEditingController _plateController;
  late final TextEditingController _yearController;
  late final TextEditingController _colorController;
  late final TextEditingController _licenseController;
  late final TextEditingController _promoController;
  bool _isApplyingPromo = false;
  String? _promoMessage;
  bool _isPromoSuccess = false;

  String _vehicleType = 'car';
  bool _hasAc = true;
  int _seats = 4;
  bool _isSavingVehicle = false;
  String? _vehicleSaveSuccess;
  String? _vehicleSaveError;

  @override
  void initState() {
    super.initState();
    _makeController = TextEditingController();
    _modelController = TextEditingController();
    _plateController = TextEditingController();
    _yearController = TextEditingController();
    _colorController = TextEditingController();
    _licenseController = TextEditingController();
    _promoController = TextEditingController();
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _plateController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    _licenseController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
      final driverProv =
          CustomChangeNotifierProvider.of<DriverProvider>(context);
      final uid = auth.currentUser.id;
      if (uid.isNotEmpty) {
        driverProv.watchDocuments(uid);
      }

      final driver = driverProv.driverProfile;
      final v = driver.vehicle;
      if (v.make.isNotEmpty && v.make != 'Toyota') {
        _makeController.text = v.make;
      }
      if (v.model.isNotEmpty && v.model != 'Camry') {
        _modelController.text = v.model;
      }
      if (v.plate.isNotEmpty && v.plate != 'SWIFT-101' && v.plate != 'ABC-1234') {
        _plateController.text = v.plate;
      }
      if (v.year >= 1995) {
        _yearController.text = v.year.toString();
      }
      if (v.color.isNotEmpty && v.color != 'Silver') {
        _colorController.text = v.color;
      }
      if (driver.licenseNumber.isNotEmpty && driver.licenseNumber != 'PK-DL-VERIFIED') {
        _licenseController.text = driver.licenseNumber;
      }
      _vehicleType = v.type;
      _hasAc = v.hasAc;
      _seats = v.seats;
      _checkPendingReferralCode(driverProv);
    }
  }

  Future<void> _checkPendingReferralCode(DriverProvider driverProv) async {
    final driver = driverProv.driverProfile;
    if (driver.referredByCode != null && driver.referredByCode!.isNotEmpty) return;
    final pending = await ReferralLinkService().checkAndCaptureInitialReferralCode();
    if (pending != null && pending.isNotEmpty && mounted) {
      if (_promoController.text.isEmpty) {
        setState(() {
          _promoController.text = pending;
          _promoMessage = 'Captain code $pending detected from referral link!';
        });
      }
    }
  }

  Future<void> _saveVehicleDetails(DriverProvider driverProv) async {
    final make = _makeController.text.trim();
    final model = _modelController.text.trim();
    final plate = _plateController.text.trim().toUpperCase();
    final year = int.tryParse(_yearController.text.trim()) ?? 0;
    final color = _colorController.text.trim();
    final license = _licenseController.text.trim();

    if (make.isEmpty || model.isEmpty || plate.isEmpty || color.isEmpty) {
      setState(() {
        _vehicleSaveError = 'Please fill in make, model, number plate, and color.';
        _vehicleSaveSuccess = null;
      });
      return;
    }

    final currentYear = DateTime.now().year;
    if (year < 1995 || year > currentYear + 1) {
      setState(() {
        _vehicleSaveError = 'Please enter a valid model year (1995 - ${currentYear + 1}).';
        _vehicleSaveSuccess = null;
      });
      return;
    }

    setState(() {
      _isSavingVehicle = true;
      _vehicleSaveError = null;
      _vehicleSaveSuccess = null;
    });

    final updatedVehicle = VehicleInfo(
      make: make,
      model: model,
      year: year,
      plate: plate,
      color: color,
      type: _vehicleType,
      hasAc: _hasAc,
      seats: _seats,
    );

    final ok = await driverProv.updateVehicleInfo(
      updatedVehicle,
      licenseNumber: license.isNotEmpty ? license : null,
    );

    if (mounted) {
      setState(() {
        _isSavingVehicle = false;
        if (ok) {
          _vehicleSaveSuccess =
              'Vehicle details saved successfully! You can now go online immediately.';
          _vehicleSaveError = null;
        } else {
          _vehicleSaveError =
              'Failed to save vehicle details. Please try again.';
        }
      });
    }
  }

  Future<void> _pickImage(DriverDocumentType type, ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() {
          _selectedFiles[type] = picked;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open camera/gallery: $e'),
            backgroundColor: AppTheme.sunsetCoral,
          ),
        );
      }
    }
  }

  Future<void> _verifyWithAi(
    DriverDocumentType type,
    DriverProvider driverProv,
    AuthProvider auth,
  ) async {
    final file = _selectedFiles[type];
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or capture a photo first.'),
          backgroundColor: AppTheme.sunsetCoral,
        ),
      );
      return;
    }

    final consented = await AiConsentDialog.ensureConsent(context);
    if (!consented || !mounted) return;

    setState(() {
      _isVerifyingType[type] = true;
    });

    try {
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = file.path.endsWith('.png') ? 'image/png' : 'image/jpeg';

      final user = auth.currentUser;
      final driver = driverProv.driverProfile;

      final expected = <String, String>{
        'fullName': user.fullName,
        'licenseNumber': _licenseController.text.trim().isNotEmpty
            ? _licenseController.text.trim()
            : driver.licenseNumber,
        'vehiclePlate': _plateController.text.trim().isNotEmpty
            ? _plateController.text.trim().toUpperCase()
            : driver.vehicle.plate,
        'vehicleModel': _modelController.text.trim().isNotEmpty
            ? '${_makeController.text.trim()} ${_modelController.text.trim()}'.trim()
            : driver.vehicle.model,
      };

      final resultDoc = await driverProv.uploadAndVerifyDocument(
        type: type,
        imageBase64: base64Image,
        rawBytes: bytes,
        mimeType: mimeType,
        expectedData: expected,
      );

      if (mounted) {
        setState(() {
          _isVerifyingType[type] = false;
        });

        if (resultDoc != null) {
          _showAiResultSheet(resultDoc);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifyingType[type] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI verification failed: $e'),
            backgroundColor: AppTheme.sunsetCoral,
          ),
        );
      }
    }
  }

  void _showAiResultSheet(DriverDocumentModel doc) {
    final layout = ResponsiveLayoutHelper(context);
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            layout.scale(20),
            layout.scale(16),
            layout.scale(20),
            layout.scale(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: doc.isVerified
                          ? AppTheme.emeraldGreen.withValues(alpha: 0.15)
                          : AppTheme.amberWarning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      doc.isVerified
                          ? Icons.verified_user_rounded
                          : Icons.warning_amber_rounded,
                      color: doc.isVerified
                          ? AppTheme.emeraldGreen
                          : AppTheme.amberWarning,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Verification Verdict',
                          style: TextStyle(
                            fontSize: layout.fontSize(16),
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          doc.type.displayName,
                          style: TextStyle(
                            fontSize: layout.fontSize(13),
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: doc.isVerified
                          ? AppTheme.emeraldGreen
                          : (doc.isRejected
                              ? AppTheme.sunsetCoral
                              : AppTheme.amberWarning),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${(doc.confidence * 100).toInt()}% Match',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.summary.isNotEmpty
                          ? doc.summary
                          : 'Document analyzed with Gemini 3.8 Flash.',
                      style: TextStyle(
                        fontSize: layout.fontSize(14),
                        height: 1.4,
                        color: c.textPrimary,
                      ),
                    ),
                    if (doc.extractedFields.idNumber != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Extracted Document ID: ${doc.extractedFields.idNumber}',
                        style: TextStyle(
                          fontSize: layout.fontSize(13),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                    if (doc.extractedFields.expiryDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Expiry Date: ${doc.extractedFields.expiryDate}',
                        style: TextStyle(
                          fontSize: layout.fontSize(12.5),
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (doc.issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Identified Issues:',
                  style: TextStyle(
                    fontSize: layout.fontSize(13),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.sunsetCoral,
                  ),
                ),
                const SizedBox(height: 4),
                for (final issue in doc.issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• $issue',
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        color: c.textSecondary,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Got It'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayoutHelper(context);
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    final driver = driverProv.driverProfile;

    final isAllVerified = driver.isVerified || driverProv.hasPassedAiVerification;

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: Text(
          'Driver Verification',
          style: TextStyle(
            fontSize: layout.fontSize(17),
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: c.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(layout.horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isAllVerified
                      ? [
                          AppTheme.emeraldGreen.withValues(alpha: 0.2),
                          AppTheme.accentCyan.withValues(alpha: 0.15)
                        ]
                      : [
                          AppTheme.primaryBlue.withValues(alpha: 0.2),
                          AppTheme.accentCyan.withValues(alpha: 0.1)
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isAllVerified
                      ? AppTheme.emeraldGreen.withValues(alpha: 0.4)
                      : AppTheme.primaryBlue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isAllVerified
                          ? AppTheme.emeraldGreen
                          : AppTheme.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAllVerified ? Icons.check : Icons.shield_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAllVerified
                              ? 'Verified Captain Account'
                              : (driver.vehicle.isConfigured
                                  ? 'Vehicle Configured • Ready to Go Online'
                                  : 'Step 1: Configure Vehicle to Go Online'),
                          style: TextStyle(
                            fontSize: layout.fontSize(15),
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAllVerified
                              ? 'All required documents verified. You have the official Verified trust badge on passenger offer cards.'
                              : (driver.vehicle.isConfigured
                                  ? 'Vehicle details saved! You can go online anytime, or verify documents below to earn your Verified badge.'
                                  : 'Enter your vehicle details below to immediately unlock the Online toggle.'),
                          style: TextStyle(
                            fontSize: layout.fontSize(12.5),
                            color: c.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _buildPromoCodeCard(
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
            ),
            const SizedBox(height: 20),

            Text(
              'Step 1: Vehicle Details — Required to Go Online',
              style: TextStyle(
                fontSize: layout.fontSize(16),
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Save your vehicle details below to immediately unlock your Online toggle and start receiving rides.',
              style: TextStyle(
                fontSize: layout.fontSize(12.5),
                color: c.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),

            _buildVehicleDetailsCard(
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
            ),
            const SizedBox(height: 24),

            // Optional Credibility Booster Section
            Text(
              'Optional: Verify Documents to Boost Credibility',
              style: TextStyle(
                fontSize: layout.fontSize(16),
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Earn a "Verified" trust badge on passenger offer cards and stand out to win more rides. Completely optional — you can go online without uploading any documents.',
              style: TextStyle(
                fontSize: layout.fontSize(12.5),
                color: c.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),

            // Badge Preview Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.accentTeal.withValues(alpha: 0.1)
                    : AppTheme.emeraldGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: AppTheme.emeraldGreen,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Verified Captain Badge',
                              style: TextStyle(
                                fontSize: layout.fontSize(13.5),
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.emeraldGreen,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'TRUST BOOST',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Passengers see a "Verified" badge next to your name and counter-offers, boosting acceptance rates.',
                          style: TextStyle(
                            fontSize: layout.fontSize(11.5),
                            color: c.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Document Cards
            _buildDocCard(
              type: DriverDocumentType.cnicFront,
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
              auth: auth,
            ),
            const SizedBox(height: 14),

            _buildDocCard(
              type: DriverDocumentType.cnicBack,
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
              auth: auth,
            ),
            const SizedBox(height: 14),

            _buildDocCard(
              type: DriverDocumentType.drivingLicense,
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
              auth: auth,
            ),
            const SizedBox(height: 14),

            _buildDocCard(
              type: DriverDocumentType.vehicleRegistration,
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
              auth: auth,
            ),
            const SizedBox(height: 14),

            _buildDocCard(
              type: DriverDocumentType.vehicleFront,
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
              auth: auth,
            ),
            const SizedBox(height: 14),

            _buildDocCard(
              type: DriverDocumentType.vehicleInterior,
              layout: layout,
              c: c,
              isDark: isDark,
              driverProv: driverProv,
              auth: auth,
            ),
            const SizedBox(height: 24),

            // AI Compliance & Security Footer Note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: AppTheme.emeraldGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All documents are encrypted with TLS 1.3 and verified using Google Gemini AI. Documents are never shared publicly or sold.',
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        color: c.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: const ReservedBottomAdBar(),
    );
  }

  Widget _buildPromoCodeCard({
    required ResponsiveLayoutHelper layout,
    required AppColors c,
    required bool isDark,
    required DriverProvider driverProv,
  }) {
    final driver = driverProv.driverProfile;
    final isWaiverActive = driver.isFeeWaiverActive;
    final hasReferredBy = driver.referredByCode != null && driver.referredByCode!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWaiverActive
              ? AppTheme.emeraldGreen.withValues(alpha: 0.4)
              : (isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isWaiverActive
                      ? AppTheme.emeraldGreen.withValues(alpha: 0.15)
                      : AppTheme.accentTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isWaiverActive ? Icons.verified_rounded : Icons.card_giftcard_rounded,
                  color: isWaiverActive ? AppTheme.emeraldGreen : AppTheme.accentTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Have a Captain Invite or Launch Code?',
                      style: TextStyle(
                        fontSize: layout.fontSize(14),
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isWaiverActive
                          ? '0% Fee Active (${driver.waiverDaysRemaining} days remaining)'
                          : 'Get 30 days of 0% platform fee (keep 100% of your fares)',
                      style: TextStyle(
                        fontSize: layout.fontSize(11.5),
                        color: isWaiverActive ? AppTheme.emeraldGreen : c.textSecondary,
                        fontWeight: isWaiverActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isWaiverActive || hasReferredBy) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.emeraldGreen, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasReferredBy
                          ? 'Applied code: ${driver.referredByCode} — 0% Fee Tier Active'
                          : '0% Platform Fee Active — You keep 100% of earnings!',
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        color: AppTheme.emeraldGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promoController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. JHANG0, CAPTAIN0 or peer code',
                      hintStyle: TextStyle(
                        fontSize: layout.fontSize(12.5),
                        color: c.textSecondary.withValues(alpha: 0.6),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.accentTeal, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isApplyingPromo
                      ? null
                      : () async {
                          final code = _promoController.text.trim();
                          if (code.isEmpty) return;
                          setState(() {
                            _isApplyingPromo = true;
                            _promoMessage = null;
                          });
                          final res = await driverProv.applyPromoCode(code);
                          if (!mounted) return;
                          setState(() {
                            _isApplyingPromo = false;
                            _promoMessage = res['message'] as String?;
                            _isPromoSuccess = res['success'] == true;
                          });
                          if (_isPromoSuccess) {
                            _promoController.clear();
                            ReferralLinkService().clearPendingReferralCode();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  ),
                  child: _isApplyingPromo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Apply',
                          style: TextStyle(
                            fontSize: layout.fontSize(13),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
            if (_promoMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _promoMessage!,
                style: TextStyle(
                  fontSize: layout.fontSize(12),
                  fontWeight: FontWeight.w600,
                  color: _isPromoSuccess ? AppTheme.emeraldGreen : AppTheme.sunsetCoral,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildVehicleDetailsCard({
    required ResponsiveLayoutHelper layout,
    required AppColors c,
    required bool isDark,
    required DriverProvider driverProv,
  }) {
    final isConfigured = driverProv.driverProfile.vehicle.isConfigured;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfigured
              ? AppTheme.emeraldGreen.withValues(alpha: 0.35)
              : (isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isConfigured ? AppTheme.emeraldGreen : AppTheme.primaryBlue)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _vehicleType == 'bike'
                      ? Icons.two_wheeler_rounded
                      : (_vehicleType == 'rikshaw'
                          ? Icons.electric_rickshaw_rounded
                          : Icons.directions_car_rounded),
                  color: isConfigured ? AppTheme.emeraldGreen : AppTheme.primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vehicle Details',
                      style: TextStyle(
                        fontSize: layout.fontSize(15),
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConfigured
                          ? '${driverProv.driverProfile.vehicle.summary} · Ready to Drive'
                          : 'Enter make, model, plate, color & specs to go online',
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: (isConfigured ? AppTheme.emeraldGreen : AppTheme.amberWarning)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isConfigured ? 'Ready' : 'Required',
                  style: TextStyle(
                    color: isConfigured ? AppTheme.emeraldGreen : AppTheme.amberWarning,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Vehicle Type Selector
          Text(
            'Vehicle Category',
            style: TextStyle(
              fontSize: layout.fontSize(12.5),
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildCategoryChip(
                label: 'Car',
                icon: Icons.directions_car_rounded,
                selected: _vehicleType == 'car',
                c: c,
                onTap: () {
                  setState(() {
                    _vehicleType = 'car';
                    _seats = 4;
                    _hasAc = true;
                  });
                },
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: 'Bike / Moto',
                icon: Icons.two_wheeler_rounded,
                selected: _vehicleType == 'bike',
                c: c,
                onTap: () {
                  setState(() {
                    _vehicleType = 'bike';
                    _seats = 1;
                    _hasAc = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: 'Auto Rikshaw',
                icon: Icons.electric_rickshaw_rounded,
                selected: _vehicleType == 'rikshaw',
                c: c,
                onTap: () {
                  setState(() {
                    _vehicleType = 'rikshaw';
                    _seats = 3;
                    _hasAc = false;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Make & Model Row
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _makeController,
                  label: 'Vehicle Make',
                  hint: _vehicleType == 'bike' ? 'Honda, United' : 'Toyota, Suzuki',
                  layout: layout,
                  c: c,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildInputField(
                  controller: _modelController,
                  label: 'Vehicle Model',
                  hint: _vehicleType == 'bike' ? 'CD 70, 125' : 'Corolla, Alto',
                  layout: layout,
                  c: c,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Plate & Year Row
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _plateController,
                  label: 'Registration Plate #',
                  hint: 'LEA-2021 / ICT-123',
                  layout: layout,
                  c: c,
                  isDark: isDark,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildInputField(
                  controller: _yearController,
                  label: 'Model Year',
                  hint: '2022',
                  layout: layout,
                  c: c,
                  isDark: isDark,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Color & License Row
          Row(
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _colorController,
                  label: 'Vehicle Color',
                  hint: 'White, Silver, Black',
                  layout: layout,
                  c: c,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildInputField(
                  controller: _licenseController,
                  label: 'Driving License #',
                  hint: 'PK-DL-XXXXXXX',
                  layout: layout,
                  c: c,
                  isDark: isDark,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
            ],
          ),

          if (_vehicleType == 'car') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Air Conditioning (AC)',
                        style: TextStyle(
                          fontSize: layout.fontSize(13),
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        _hasAc ? 'AC Comfort Tier' : 'Non-AC Economy',
                        style: TextStyle(
                          fontSize: layout.fontSize(11),
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _hasAc,
                  onChanged: (val) => setState(() => _hasAc = val),
                  activeTrackColor: AppTheme.emeraldGreen,
                ),
              ],
            ),
          ],

          if (_vehicleSaveError != null) ...[
            const SizedBox(height: 10),
            Text(
              _vehicleSaveError!,
              style: TextStyle(
                color: AppTheme.sunsetCoral,
                fontSize: layout.fontSize(12),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          if (_vehicleSaveSuccess != null) ...[
            const SizedBox(height: 10),
            Text(
              _vehicleSaveSuccess!,
              style: TextStyle(
                color: AppTheme.emeraldGreen,
                fontSize: layout.fontSize(12),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _isSavingVehicle ? null : () => _saveVehicleDetails(driverProv),
            icon: _isSavingVehicle
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_isSavingVehicle ? 'Saving Details...' : 'Save Vehicle Details'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required IconData icon,
    required bool selected,
    required AppColors c,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryBlue
                : c.border.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primaryBlue : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : c.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ResponsiveLayoutHelper layout,
    required AppColors c,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: layout.fontSize(11.5),
            fontWeight: FontWeight.w700,
            color: c.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: TextStyle(
            fontSize: layout.fontSize(13),
            color: c.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: layout.fontSize(12),
              color: c.textMuted,
            ),
            isDense: true,
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocCard({
    required DriverDocumentType type,
    required ResponsiveLayoutHelper layout,
    required AppColors c,
    required bool isDark,
    required DriverProvider driverProv,
    required AuthProvider auth,
  }) {
    // Check if document is already saved in driver provider
    final savedDoc = driverProv.documents.firstWhere(
      (d) => d.type == type,
      orElse: () => DriverDocumentModel(
        id: type.code,
        type: type,
        status: driverProv.driverProfile.isVerified
            ? DocVerificationStatus.verified
            : DocVerificationStatus.pending,
      ),
    );

    final localFile = _selectedFiles[type];
    final isVerifying = _isVerifyingType[type] ?? false;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (savedDoc.status) {
      case DocVerificationStatus.verified:
        statusColor = AppTheme.emeraldGreen;
        statusLabel = 'Verified';
        statusIcon = Icons.check_circle_rounded;
        break;
      case DocVerificationStatus.verifying:
        statusColor = AppTheme.primaryBlue;
        statusLabel = 'Verifying...';
        statusIcon = Icons.autorenew_rounded;
        break;
      case DocVerificationStatus.needsReview:
        statusColor = AppTheme.amberWarning;
        statusLabel = 'Needs Review';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case DocVerificationStatus.rejected:
        statusColor = AppTheme.sunsetCoral;
        statusLabel = 'Rejected';
        statusIcon = Icons.cancel_rounded;
        break;
      case DocVerificationStatus.pending:
        statusColor = localFile != null ? AppTheme.primaryBlue : c.textMuted;
        statusLabel = localFile != null ? 'Ready to Verify' : 'Not Uploaded';
        statusIcon = localFile != null
            ? Icons.file_upload_outlined
            : Icons.radio_button_unchecked;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: savedDoc.isVerified
              ? AppTheme.emeraldGreen.withValues(alpha: 0.35)
              : (isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.displayName,
                      style: TextStyle(
                        fontSize: layout.fontSize(15),
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.description,
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (localFile != null && !savedDoc.isVerified) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.image, size: 18, color: AppTheme.accentCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localFile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedFiles[type] = null;
                      });
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          ],
          if (savedDoc.isVerified && savedDoc.extractedFields.idNumber != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.emeraldGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppTheme.emeraldGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI Extracted: ${savedDoc.extractedFields.idNumber} (${(savedDoc.confidence * 100).toInt()}% confidence)',
                      style: TextStyle(
                        fontSize: layout.fontSize(12),
                        fontWeight: FontWeight.w600,
                        color: AppTheme.emeraldGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isVerifying
                      ? null
                      : () => _pickImage(type, ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isVerifying
                      ? null
                      : () => _pickImage(type, ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (localFile != null && !savedDoc.isVerified) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: isVerifying
                        ? null
                        : () => _verifyWithAi(type, driverProv, auth),
                    icon: isVerifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(isVerifying ? 'Analyzing...' : 'Verify with AI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
