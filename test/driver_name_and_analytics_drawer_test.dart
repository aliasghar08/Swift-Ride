import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/domain/models/driver_khata_model.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/presentation/driver/widgets/driver_analytics_drawer.dart';
import 'package:swiftride/presentation/driver/widgets/driver_name_dialog.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/services/driver_khata_service.dart';

void main() {
  group('Driver Name Validation Tests', () {
    test('isDefaultDriverName detects default placeholders correctly', () {
      expect(isDefaultDriverName(null), isTrue);
      expect(isDefaultDriverName(''), isTrue);
      expect(isDefaultDriverName('   '), isTrue);
      expect(isDefaultDriverName('Swift Ride User'), isTrue);
      expect(isDefaultDriverName('swiftride user'), isTrue);
      expect(isDefaultDriverName('SWIFTRIDE USER'), isTrue);
      expect(isDefaultDriverName('Driver'), isTrue);
      expect(isDefaultDriverName('guest user'), isTrue);
      expect(isDefaultDriverName('user'), isTrue);
      expect(isDefaultDriverName('rider'), isTrue);

      expect(isDefaultDriverName('Tariq Mehmood'), isFalse);
      expect(isDefaultDriverName('Ali Asghar'), isFalse);
      expect(isDefaultDriverName('Bilal Khan'), isFalse);
    });
  });

  group('DriverAnalyticsDrawer Widget Tests', () {
    testWidgets('Renders driver name, rating, vehicle, 2% fee, and khata metrics',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final user = AppUser(
        id: 'driver_123',
        phone: '+923001234567',
        fullName: 'Tariq Mehmood',
        role: UserRole.driver,
        rating: 4.9,
        createdAt: DateTime.now(),
      );

      final auth = AuthProvider(initialUser: user, initialRole: UserRole.driver);
      final driverProv = DriverProvider();
      driverProv.updateProfile(
        DriverProfile(
          userId: 'driver_123',
          licenseNumber: 'DL-998877',
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2021,
            plate: 'LEA-4567',
            color: 'White',
            type: 'car',
          ),
          isVerified: true,
          rating: 4.9,
          totalEarnings: 10000.0,
          totalRides: 25,
          createdAt: DateTime.now(),
          subscriptionExpiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomChangeNotifierProvider<AuthProvider>(
              notifier: auth,
              child: CustomChangeNotifierProvider<DriverProvider>(
                notifier: driverProv,
                child: const DriverAnalyticsDrawer(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check Header Details
      expect(find.text('Tariq Mehmood'), findsOneWidget);
      expect(find.text('+923001234567'), findsOneWidget);
      expect(find.text('4.9'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.textContaining('Toyota Corolla'), findsOneWidget);
      expect(find.textContaining('LEA-4567'), findsOneWidget);

      // Check 2% Platform Economics
      expect(find.textContaining('Driver Share (98%)'), findsOneWidget);
      expect(find.textContaining('Platform Fee (2%)'), findsOneWidget);
      expect(find.textContaining('Year 1 Guarantee: Fixed 2% fee'), findsOneWidget);

      // Check Performance Stats
      expect(find.text('25'), findsOneWidget); // Total rides
      expect(find.text('98.5%'), findsOneWidget); // Acceptance
      expect(find.text('99.1%'), findsOneWidget); // Completion
    });
  });

  group('DriverNameDialog Widget Tests', () {
    testWidgets('Displays warning on empty or default name submission',
        (tester) async {
      final user = AppUser(
        id: 'driver_456',
        phone: '+923009876543',
        fullName: 'Swift Ride User',
        role: UserRole.driver,
        createdAt: DateTime.now(),
      );

      final auth = AuthProvider(initialUser: user, initialRole: UserRole.driver);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomChangeNotifierProvider<AuthProvider>(
              notifier: auth,
              child: const DriverNameDialog(initialName: 'Swift Ride User'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Driver Identity Verification'), findsOneWidget);

      // Tap Save with empty text
      await tester.tap(find.text('Save Name'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter at least 3 characters.'), findsOneWidget);

      // Enter a placeholder name
      await tester.enterText(find.byType(TextField), 'Driver');
      await tester.tap(find.text('Save Name'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your actual legal full name.'), findsOneWidget);
    });
  });
}
