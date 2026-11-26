import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/utils/vehicle_validator.dart';
import 'package:swiftride/domain/models/vehicle_presets.dart';
import 'package:swiftride/presentation/common/human_verification_widget.dart';

void main() {
  group('HumanVerificationController & Widget Tests', () {
    test('controller starts unverified and can simulate verification and reset', () {
      final controller = HumanVerificationController();
      expect(controller.isVerified, isFalse);
      expect(controller.token, isNull);

      // Simulate verification
      final token = controller.simulateVerification('test_token_123');
      expect(token, 'test_token_123');
      expect(controller.isVerified, isTrue);
      expect(controller.token, 'test_token_123');

      // Reset
      controller.reset();
      expect(controller.isVerified, isFalse);
      expect(controller.token, isNull);
    });

    testWidgets('HumanVerificationWidget renders challenge and responds to simulation', (tester) async {
      final controller = HumanVerificationController();
      String? emittedToken;
      bool expired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HumanVerificationWidget(
              controller: controller,
              onVerified: (t) => emittedToken = t,
              onExpired: () => expired = true,
            ),
          ),
        ),
      );

      // Initial unverified state
      expect(find.text('I am not a robot (Tap to verify)'), findsOneWidget);
      expect(emittedToken, isNull);
      expect(expired, isFalse);

      // Trigger simulation via controller
      controller.simulateVerification('mock_human_token');
      await tester.pumpAndSettle();

      expect(controller.isVerified, isTrue);
      expect(emittedToken, 'mock_human_token');
      expect(find.text('Human Verification Confirmed'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Reset
      controller.reset();
      await tester.pumpAndSettle();
      expect(controller.isVerified, isFalse);
      expect(find.text('I am not a robot (Tap to verify)'), findsOneWidget);
    });
  });

  group('VehicleValidator Tests', () {
    test('normalizeLicensePlate formats correctly', () {
      expect(VehicleValidator.normalizeLicensePlate('lea 2021'), 'LEA-2021');
      expect(VehicleValidator.normalizeLicensePlate('  jhg-412 '), 'JHG-412');
      expect(VehicleValidator.normalizeLicensePlate('ict_24_889'), 'ICT-24-889');
      expect(VehicleValidator.normalizeLicensePlate('fsd//123'), 'FSD-123');
      expect(VehicleValidator.normalizeLicensePlate('lea2021'), 'LEA-2021');
      expect(VehicleValidator.normalizeLicensePlate(''), '');
      expect(VehicleValidator.normalizeLicensePlate(null), '');
    });

    test('normalizeLicenseNumber formats correctly', () {
      expect(VehicleValidator.normalizeLicenseNumber('pk dl 123456'), 'PK-DL-123456');
      expect(VehicleValidator.normalizeLicenseNumber(' pb-998877 '), 'PB-998877');
      expect(VehicleValidator.normalizeLicenseNumber(''), '');
      expect(VehicleValidator.normalizeLicenseNumber(null), '');
    });

    test('validateLicensePlate accepts genuine Pakistani plates and rejects invalid/dummy ones', () {
      // Genuine plates
      expect(VehicleValidator.validateLicensePlate('JHG-412'), isNull);
      expect(VehicleValidator.validateLicensePlate('LEA-2021'), isNull);
      expect(VehicleValidator.validateLicensePlate('ICT-24-889'), isNull);
      expect(VehicleValidator.validateLicensePlate('LHR-9999'), isNull);
      expect(VehicleValidator.validateLicensePlate('KHI-123-A'), isNull);

      // Empty or malformed
      expect(VehicleValidator.validateLicensePlate(''), isNotNull);
      expect(VehicleValidator.validateLicensePlate('12345'), isNotNull);
      expect(VehicleValidator.validateLicensePlate('ABC'), isNotNull);
      expect(VehicleValidator.validateLicensePlate('TOOLONGLICENSE-12345'), isNotNull);

      // Dummy or placeholder plates
      expect(VehicleValidator.validateLicensePlate('AAA-0000'), isNotNull);
      expect(VehicleValidator.validateLicensePlate('XXX-1234'), isNotNull);
      expect(VehicleValidator.validateLicensePlate('TEST-123'), isNotNull);
      expect(VehicleValidator.validateLicensePlate('000-0000'), isNotNull);
      expect(VehicleValidator.validateLicensePlate('LEA-0000'), isNotNull);
    });

    test('validateMakeModel enforces genuine make and model', () {
      expect(VehicleValidator.validateMakeModel(make: 'Toyota', model: 'Corolla'), isNull);
      expect(VehicleValidator.validateMakeModel(make: 'Honda', model: 'CD 70'), isNull);
      expect(VehicleValidator.validateMakeModel(make: 'Changan', model: 'Karvaan'), isNull);
      expect(VehicleValidator.validateMakeModel(make: 'Sazgar', model: '4-Stroke'), isNull);

      // Invalid make
      expect(VehicleValidator.validateMakeModel(make: '', model: 'Corolla'), isNotNull);
      expect(VehicleValidator.validateMakeModel(make: 'T', model: 'Corolla'), isNotNull);
      expect(VehicleValidator.validateMakeModel(make: '123', model: 'Corolla'), isNotNull);
      expect(VehicleValidator.validateMakeModel(make: 'test', model: 'Corolla'), isNotNull);

      // Invalid model
      expect(VehicleValidator.validateMakeModel(make: 'Toyota', model: ''), isNotNull);
      expect(VehicleValidator.validateMakeModel(make: 'Toyota', model: 'C'), isNotNull);
      expect(VehicleValidator.validateMakeModel(make: 'Toyota', model: '123'), isNotNull);
      expect(VehicleValidator.validateMakeModel(make: 'Toyota', model: 'asdf'), isNotNull);
    });

    test('validateModelYear validates valid range 1995 to next year', () {
      final currentYear = DateTime.now().year;
      expect(VehicleValidator.validateModelYear(currentYear), isNull);
      expect(VehicleValidator.validateModelYear(currentYear + 1), isNull);
      expect(VehicleValidator.validateModelYear(2015), isNull);
      expect(VehicleValidator.validateModelYear(1995), isNull);

      expect(VehicleValidator.validateModelYear(1994), isNotNull);
      expect(VehicleValidator.validateModelYear(currentYear + 2), isNotNull);
      expect(VehicleValidator.validateModelYear('invalid'), isNotNull);
      expect(VehicleValidator.validateModelYear(null), isNotNull);
    });

    test('validateColor accepts valid color names and rejects numbers/placeholders', () {
      expect(VehicleValidator.validateColor('White'), isNull);
      expect(VehicleValidator.validateColor('Silver'), isNull);
      expect(VehicleValidator.validateColor('Pearl White'), isNull);
      expect(VehicleValidator.validateColor('Gun Metallic'), isNull);

      expect(VehicleValidator.validateColor(''), isNotNull);
      expect(VehicleValidator.validateColor('W'), isNotNull);
      expect(VehicleValidator.validateColor('12345'), isNotNull);
      expect(VehicleValidator.validateColor('test'), isNotNull);
      expect(VehicleValidator.validateColor('none'), isNotNull);
    });

    test('validateLicenseNumber validates length and rejects dummy patterns', () {
      expect(VehicleValidator.validateLicenseNumber('PK-DL-123456'), isNull);
      expect(VehicleValidator.validateLicenseNumber('PB-9876543'), isNull);
      expect(VehicleValidator.validateLicenseNumber('ICT-445566'), isNull);

      expect(VehicleValidator.validateLicenseNumber(''), isNotNull);
      expect(VehicleValidator.validateLicenseNumber('123'), isNotNull);
      expect(VehicleValidator.validateLicenseNumber('000000'), isNotNull);
      expect(VehicleValidator.validateLicenseNumber('123456'), isNotNull);
      expect(VehicleValidator.validateLicenseNumber('TEST123'), isNotNull);
    });

    test('getCategorySeats and getCategoryAllowsAc enforce category specifications', () {
      expect(VehicleValidator.getCategorySeats('car'), 4);
      expect(VehicleValidator.getCategoryAllowsAc('car'), isTrue);

      expect(VehicleValidator.getCategorySeats('sevenSeater'), 6);
      expect(VehicleValidator.getCategoryAllowsAc('sevenSeater'), isTrue);

      expect(VehicleValidator.getCategorySeats('bike'), 1);
      expect(VehicleValidator.getCategoryAllowsAc('bike'), isFalse);

      expect(VehicleValidator.getCategorySeats('rikshaw'), 3);
      expect(VehicleValidator.getCategoryAllowsAc('rikshaw'), isFalse);
    });
  });

  group('VehiclePresets Tests', () {
    test('modelsFor returns correct presets per vehicle type', () {
      final cars = VehiclePresets.modelsFor('car');
      expect(cars, contains('Toyota Corolla'));
      expect(cars, contains('Suzuki Alto'));

      final bikes = VehiclePresets.modelsFor('bike');
      expect(bikes, contains('Honda CD 70'));
      expect(bikes, contains('Yamaha YBR 125'));

      final rikshaws = VehiclePresets.modelsFor('rikshaw');
      expect(rikshaws, contains('Sazgar 4-Stroke'));

      final sevenSeaters = VehiclePresets.modelsFor('sevenSeater');
      expect(sevenSeaters, contains('Changan Karvaan'));
      expect(sevenSeaters, contains('Suzuki Every'));
    });

    test('platePrefixes, modelYears, colors, and licensePrefixes are populated', () {
      expect(VehiclePresets.platePrefixes, contains('JHG-'));
      expect(VehiclePresets.platePrefixes, contains('LEA-'));
      expect(VehiclePresets.platePrefixes, contains('ICT-'));

      expect(VehiclePresets.modelYears.first, DateTime.now().year + 1);
      expect(VehiclePresets.modelYears.last, 2005);

      expect(VehiclePresets.colors.any((c) => c.name == 'White'), isTrue);
      expect(VehiclePresets.colors.any((c) => c.name == 'Silver'), isTrue);
      expect(VehiclePresets.colors.any((c) => c.name == 'Black'), isTrue);

      expect(VehiclePresets.licensePrefixes, contains('PK-DL-'));
      expect(VehiclePresets.licensePrefixes, contains('PB-'));
      expect(VehiclePresets.licensePrefixes, contains('ICT-'));
    });
  });
}
