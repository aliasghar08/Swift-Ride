import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/domain/models/driver_document_model.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/presentation/driver/driver_verification_screen.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';

void main() {
  group('Driver Document Domain & Model Tests', () {
    test('DriverDocumentType mappings and serialization', () {
      expect(DriverDocumentType.cnicFront.code, 'CNIC_FRONT');
      expect(DriverDocumentType.cnicBack.code, 'CNIC_BACK');
      expect(DriverDocumentType.drivingLicense.code, 'DRIVING_LICENSE');
      expect(DriverDocumentType.vehicleRegistration.code, 'VEHICLE_REGISTRATION');
      expect(DriverDocumentType.vehicleFront.code, 'VEHICLE_FRONT');
      expect(DriverDocumentType.vehicleInterior.code, 'VEHICLE_INTERIOR');

      expect(DriverDocumentTypeX.fromCode('CNIC_FRONT'), DriverDocumentType.cnicFront);
      expect(DriverDocumentTypeX.fromCode('cnic_back'), DriverDocumentType.cnicBack);
      expect(DriverDocumentTypeX.fromCode('DRIVING_LICENSE'), DriverDocumentType.drivingLicense);
      expect(DriverDocumentTypeX.fromCode('VEHICLE_REGISTRATION'), DriverDocumentType.vehicleRegistration);
      expect(DriverDocumentTypeX.fromCode('VEHICLE_FRONT'), DriverDocumentType.vehicleFront);
      expect(DriverDocumentTypeX.fromCode('VEHICLE_INTERIOR'), DriverDocumentType.vehicleInterior);
      expect(DriverDocumentTypeX.fromCode('UNKNOWN'), DriverDocumentType.cnicFront);
    });

    test('VehicleInfo.isConfigured checks for non-placeholder legal details', () {
      const placeholderVehicle = VehicleInfo(
        make: '',
        model: '',
        year: 0,
        plate: '',
        color: '',
      );
      expect(placeholderVehicle.isConfigured, isFalse);

      const defaultPlaceholder = VehicleInfo(
        make: 'Toyota',
        model: 'Camry',
        year: 2022,
        plate: 'SWIFT-101',
        color: 'Silver',
      );
      expect(defaultPlaceholder.isConfigured, isFalse);

      const configuredVehicle = VehicleInfo(
        make: 'Suzuki',
        model: 'Alto',
        year: 2021,
        plate: 'LEA-21-4567',
        color: 'White',
      );
      expect(configuredVehicle.isConfigured, isTrue);
    });

    test('DocVerificationStatus mappings', () {
      expect(DocVerificationStatus.pending.code, 'PENDING');
      expect(DocVerificationStatus.verifying.code, 'VERIFYING');
      expect(DocVerificationStatus.verified.code, 'VERIFIED');
      expect(DocVerificationStatus.needsReview.code, 'NEEDS_REVIEW');
      expect(DocVerificationStatus.rejected.code, 'REJECTED');

      expect(DocVerificationStatusX.fromCode('VERIFIED'), DocVerificationStatus.verified);
      expect(DocVerificationStatusX.fromCode('NEEDS_REVIEW'), DocVerificationStatus.needsReview);
      expect(DocVerificationStatusX.fromCode('REJECTED'), DocVerificationStatus.rejected);
      expect(DocVerificationStatusX.fromCode('INVALID'), DocVerificationStatus.pending);
    });

    test('AiExtractedFields serialization and hasAnyField getter', () {
      const emptyFields = AiExtractedFields();
      expect(emptyFields.hasAnyField, isFalse);

      const fields = AiExtractedFields(
        fullName: 'Muhammad Ali',
        idNumber: '35201-1234567-1',
        expiryDate: '2028-12-31',
        issueDate: '2018-12-31',
        vehiclePlate: 'LEA-24-1234',
      );
      expect(fields.hasAnyField, isTrue);

      final map = fields.toMap();
      expect(map['fullName'], 'Muhammad Ali');
      expect(map['idNumber'], '35201-1234567-1');

      final deserialized = AiExtractedFields.fromMap(map);
      expect(deserialized.fullName, 'Muhammad Ali');
      expect(deserialized.idNumber, '35201-1234567-1');
      expect(deserialized.expiryDate, '2028-12-31');
    });

    test('DriverDocumentModel serialization from and to map', () {
      final doc = DriverDocumentModel(
        id: 'CNIC_FRONT',
        type: DriverDocumentType.cnicFront,
        status: DocVerificationStatus.verified,
        confidence: 0.95,
        summary: 'CNIC matches Pakistani standard NADRA format.',
        extractedFields: const AiExtractedFields(
          fullName: 'Ali Asghar',
          idNumber: '35202-9876543-1',
        ),
        issues: const [],
      );

      final map = doc.toMap();
      expect(map['documentType'], 'CNIC_FRONT');
      expect(map['status'], 'VERIFIED');
      expect(map['confidence'], 0.95);
      expect(map['isVerified'], isTrue);

      final deserialized = DriverDocumentModel.fromMap(map, 'CNIC_FRONT');
      expect(deserialized.type, DriverDocumentType.cnicFront);
      expect(deserialized.status, DocVerificationStatus.verified);
      expect(deserialized.confidence, 0.95);
      expect(deserialized.extractedFields.fullName, 'Ali Asghar');
      expect(deserialized.extractedFields.idNumber, '35202-9876543-1');
    });
  });

  group('DriverProvider AI Verification Evaluation Tests', () {
    test('hasPassedAiVerification requires CNIC front and Driving license verified >= 0.80', () {
      final driverProv = DriverProvider();

      // Initially no documents -> false
      expect(driverProv.hasPassedAiVerification, isFalse);

      // Only CNIC Front verified -> still false (license needed)
      driverProv.setDocumentsForTesting([
        const DriverDocumentModel(
          id: 'CNIC_FRONT',
          type: DriverDocumentType.cnicFront,
          status: DocVerificationStatus.verified,
          confidence: 0.92,
        ),
      ]);
      expect(driverProv.hasPassedAiVerification, isFalse);

      // CNIC Front (0.92) + License flagged for review (0.65) -> false
      driverProv.setDocumentsForTesting([
        const DriverDocumentModel(
          id: 'CNIC_FRONT',
          type: DriverDocumentType.cnicFront,
          status: DocVerificationStatus.verified,
          confidence: 0.92,
        ),
        const DriverDocumentModel(
          id: 'DRIVING_LICENSE',
          type: DriverDocumentType.drivingLicense,
          status: DocVerificationStatus.needsReview,
          confidence: 0.65,
        ),
      ]);
      expect(driverProv.hasPassedAiVerification, isFalse);

      // Both CNIC Front and Driving License verified -> true
      driverProv.setDocumentsForTesting([
        const DriverDocumentModel(
          id: 'CNIC_FRONT',
          type: DriverDocumentType.cnicFront,
          status: DocVerificationStatus.verified,
          confidence: 0.92,
        ),
        const DriverDocumentModel(
          id: 'DRIVING_LICENSE',
          type: DriverDocumentType.drivingLicense,
          status: DocVerificationStatus.verified,
          confidence: 0.88,
        ),
      ]);
      expect(driverProv.hasPassedAiVerification, isTrue);

      // canActAsDriver requires both verified documents AND configured vehicle
      expect(driverProv.canActAsDriver, isFalse);

      driverProv.setDriverProfileForTesting(
        driverProv.driverProfile.copyWith(
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'ICT-22-999',
            color: 'White',
          ),
        ),
      );
      expect(driverProv.canActAsDriver, isTrue);
    });
  });

  group('DriverVerificationScreen Widget Rendering Tests', () {
    testWidgets('Renders DriverVerificationScreen header, vehicle details card, and all document cards', (tester) async {
      final authProv = AuthProvider(
        initialUser: AppUser(
          id: 'test_driver_101',
          phone: '+923001234567',
          fullName: 'Test Driver',
          role: UserRole.driver,
          rating: 5.0,
          totalRides: 0,
          createdAt: DateTime.now(),
        ),
        initialRole: UserRole.driver,
      );

      final driverProv = DriverProvider(
        initialProfile: DriverProfile.empty(userId: 'test_driver_101'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomChangeNotifierProvider<AuthProvider>(
            notifier: authProv,
            child: CustomChangeNotifierProvider<DriverProvider>(
              notifier: driverProv,
              child: const DriverVerificationScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and titles
      expect(find.text('Driver Verification'), findsOneWidget);
      expect(find.text('Pending Document Verification'), findsOneWidget);
      expect(find.text('Vehicle Information (Legal & Visual)'), findsOneWidget);
      expect(find.text('Required Documents'), findsOneWidget);

      // Check vehicle details fields & save button
      expect(find.text('Save Vehicle Details'), findsOneWidget);
      expect(find.text('Vehicle Make'), findsOneWidget);
      expect(find.text('Vehicle Model'), findsOneWidget);
      expect(find.text('Registration Plate #'), findsOneWidget);

      // Check all document & visual inspection card titles
      expect(find.text('CNIC (Front)'), findsOneWidget);
      expect(find.text('CNIC (Back)'), findsOneWidget);
      expect(find.text('Driving License'), findsOneWidget);
      expect(find.text('Vehicle Registration'), findsOneWidget);
      expect(find.text('Vehicle Front (Plate Visible)'), findsOneWidget);
      expect(find.text('Vehicle Interior (Cabin & Seats)'), findsOneWidget);

      // Check action buttons exist
      expect(find.text('Camera'), findsWidgets);
      expect(find.text('Gallery'), findsWidgets);
    });
  });
}
