import 'package:flutter/foundation.dart';

/// Categories of identity and vehicle documentation required for Pakistani drivers.
enum DriverDocumentType {
  cnicFront,
  cnicBack,
  drivingLicense,
  vehicleRegistration,
  vehicleFront,
  vehicleInterior,
}

extension DriverDocumentTypeX on DriverDocumentType {
  String get code {
    switch (this) {
      case DriverDocumentType.cnicFront:
        return 'CNIC_FRONT';
      case DriverDocumentType.cnicBack:
        return 'CNIC_BACK';
      case DriverDocumentType.drivingLicense:
        return 'DRIVING_LICENSE';
      case DriverDocumentType.vehicleRegistration:
        return 'VEHICLE_REGISTRATION';
      case DriverDocumentType.vehicleFront:
        return 'VEHICLE_FRONT';
      case DriverDocumentType.vehicleInterior:
        return 'VEHICLE_INTERIOR';
    }
  }

  String get displayName {
    switch (this) {
      case DriverDocumentType.cnicFront:
        return 'CNIC (Front)';
      case DriverDocumentType.cnicBack:
        return 'CNIC (Back)';
      case DriverDocumentType.drivingLicense:
        return 'Driving License';
      case DriverDocumentType.vehicleRegistration:
        return 'Vehicle Registration';
      case DriverDocumentType.vehicleFront:
        return 'Vehicle Front (Plate Visible)';
      case DriverDocumentType.vehicleInterior:
        return 'Vehicle Interior (Cabin & Seats)';
    }
  }

  String get description {
    switch (this) {
      case DriverDocumentType.cnicFront:
        return 'Front side showing your photo, 13-digit CNIC, and name';
      case DriverDocumentType.cnicBack:
        return 'Back side showing your permanent address and barcode';
      case DriverDocumentType.drivingLicense:
        return 'Valid Pakistani driving license (LTV/HTV/Motorcycle)';
      case DriverDocumentType.vehicleRegistration:
        return 'Vehicle smart card or excise registration book';
      case DriverDocumentType.vehicleFront:
        return 'Clear photo of front bumper showing registration plate and vehicle body';
      case DriverDocumentType.vehicleInterior:
        return 'Clear photo of passenger seats, interior cleanliness, and cabin condition';
    }
  }

  static DriverDocumentType fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'CNIC_FRONT':
        return DriverDocumentType.cnicFront;
      case 'CNIC_BACK':
        return DriverDocumentType.cnicBack;
      case 'DRIVING_LICENSE':
        return DriverDocumentType.drivingLicense;
      case 'VEHICLE_REGISTRATION':
        return DriverDocumentType.vehicleRegistration;
      case 'VEHICLE_FRONT':
        return DriverDocumentType.vehicleFront;
      case 'VEHICLE_INTERIOR':
        return DriverDocumentType.vehicleInterior;
      default:
        return DriverDocumentType.cnicFront;
    }
  }
}

/// Verification outcome states.
enum DocVerificationStatus {
  pending,
  verifying,
  verified,
  needsReview,
  rejected,
}

extension DocVerificationStatusX on DocVerificationStatus {
  String get code {
    switch (this) {
      case DocVerificationStatus.pending:
        return 'PENDING';
      case DocVerificationStatus.verifying:
        return 'VERIFYING';
      case DocVerificationStatus.verified:
        return 'VERIFIED';
      case DocVerificationStatus.needsReview:
        return 'NEEDS_REVIEW';
      case DocVerificationStatus.rejected:
        return 'REJECTED';
    }
  }

  static DocVerificationStatus fromCode(String? code) {
    switch (code?.toUpperCase()) {
      case 'VERIFIED':
        return DocVerificationStatus.verified;
      case 'VERIFYING':
        return DocVerificationStatus.verifying;
      case 'NEEDS_REVIEW':
        return DocVerificationStatus.needsReview;
      case 'REJECTED':
        return DocVerificationStatus.rejected;
      case 'PENDING':
      default:
        return DocVerificationStatus.pending;
    }
  }
}

/// Extracted OCR & validation data returned from Gemini AI inspection.
class AiExtractedFields {
  final String? fullName;
  final String? idNumber;
  final String? expiryDate;
  final String? issueDate;
  final String? vehiclePlate;

  const AiExtractedFields({
    this.fullName,
    this.idNumber,
    this.expiryDate,
    this.issueDate,
    this.vehiclePlate,
  });

  bool get hasAnyField =>
      (fullName != null && fullName!.isNotEmpty) ||
      (idNumber != null && idNumber!.isNotEmpty) ||
      (expiryDate != null && expiryDate!.isNotEmpty) ||
      (issueDate != null && issueDate!.isNotEmpty) ||
      (vehiclePlate != null && vehiclePlate!.isNotEmpty);

  factory AiExtractedFields.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AiExtractedFields();
    return AiExtractedFields(
      fullName: map['fullName'] as String?,
      idNumber: map['idNumber'] as String?,
      expiryDate: map['expiryDate'] as String?,
      issueDate: map['issueDate'] as String?,
      vehiclePlate: map['vehiclePlate'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'idNumber': idNumber,
        'expiryDate': expiryDate,
        'issueDate': issueDate,
        'vehiclePlate': vehiclePlate,
      };
}

/// Model representing a driver's uploaded document and its AI inspection verdict.
@immutable
class DriverDocumentModel {
  final String id;
  final DriverDocumentType type;
  final DocVerificationStatus status;
  final double confidence;
  final AiExtractedFields extractedFields;
  final List<String> issues;
  final String summary;
  final String? localPath;
  final String? downloadUrl;
  final DateTime? verifiedAt;
  final DateTime? updatedAt;

  const DriverDocumentModel({
    required this.id,
    required this.type,
    this.status = DocVerificationStatus.pending,
    this.confidence = 0.0,
    this.extractedFields = const AiExtractedFields(),
    this.issues = const [],
    this.summary = '',
    this.localPath,
    this.downloadUrl,
    this.verifiedAt,
    this.updatedAt,
  });

  bool get isVerified => status == DocVerificationStatus.verified;
  bool get isRejected => status == DocVerificationStatus.rejected;
  bool get needsReview => status == DocVerificationStatus.needsReview;

  factory DriverDocumentModel.fromMap(Map<String, dynamic> map, String id) {
    return DriverDocumentModel(
      id: id,
      type: DriverDocumentTypeX.fromCode(map['documentType'] ?? id),
      status: DocVerificationStatusX.fromCode(map['status'] as String?),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      extractedFields: AiExtractedFields.fromMap(
        map['extractedFields'] as Map<String, dynamic>?,
      ),
      issues: (map['issues'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      summary: (map['summary'] as String?) ?? '',
      downloadUrl: map['downloadUrl'] as String?,
      verifiedAt: map['verifiedAt'] != null
          ? (map['verifiedAt'] as dynamic).toDate()
          : null,
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'documentType': type.code,
        'status': status.code,
        'confidence': confidence,
        'extractedFields': extractedFields.toMap(),
        'issues': issues,
        'summary': summary,
        'downloadUrl': downloadUrl,
        'isVerified': isVerified,
      };

  DriverDocumentModel copyWith({
    String? id,
    DriverDocumentType? type,
    DocVerificationStatus? status,
    double? confidence,
    AiExtractedFields? extractedFields,
    List<String>? issues,
    String? summary,
    String? localPath,
    String? downloadUrl,
    DateTime? verifiedAt,
    DateTime? updatedAt,
  }) {
    return DriverDocumentModel(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      extractedFields: extractedFields ?? this.extractedFields,
      issues: issues ?? this.issues,
      summary: summary ?? this.summary,
      localPath: localPath ?? this.localPath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
