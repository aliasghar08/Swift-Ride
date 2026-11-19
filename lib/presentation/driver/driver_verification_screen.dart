import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/driver_document_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../view_models/responsive_layout_helper.dart';

/// Screen allowing drivers to upload official Pakistani documents (CNIC, Driving License,
/// Vehicle Registration) and run real-time AI-powered inspection via Google Gemini 3.8 Flash.
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
        'licenseNumber': driver.licenseNumber,
        'vehiclePlate': driver.vehicle.plate,
        'vehicleModel': driver.vehicle.model,
      };

      final resultDoc = await driverProv.uploadAndVerifyDocument(
        type: type,
        imageBase64: base64Image,
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
                              : 'Pending Document Verification',
                          style: TextStyle(
                            fontSize: layout.fontSize(15),
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAllVerified
                              ? 'All required documents verified. You can toggle Online anytime.'
                              : 'Upload clear photos of your CNIC and License for instant AI verification.',
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
            const SizedBox(height: 20),

            Text(
              'Required Documents',
              style: TextStyle(
                fontSize: layout.fontSize(16),
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

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
