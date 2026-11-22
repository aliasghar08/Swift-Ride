import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/presentation/driver/widgets/driver_status_credibility_dialog.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/services/firestore/firestore_driver_service.dart';
import 'package:swiftride/services/native/native_storage_service.dart';

class FakeFirestoreDriverService implements FirestoreDriverService {
  @override
  Future<String?> setOnline({
    required bool isOnline,
    double? latitude,
    double? longitude,
    bool? femalePassengersOnly,
  }) async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Driver Online By Default & Persistence Tests', () {
    test('driver_explicitly_offline defaults to false', () async {
      final storage = NativeStorageService();
      await storage.remove('driver_explicitly_offline');
      final explicitlyOffline = await storage.getBool('driver_explicitly_offline') ?? false;
      expect(explicitlyOffline, isFalse);
    });

    test('checkAndAutoGoOnline keeps unverified driver offline without configured vehicle', () async {
      final storage = NativeStorageService();
      await storage.remove('driver_explicitly_offline');

      final viewModel = DriverViewModel();
      final driverProv = DriverProvider(firestoreService: FakeFirestoreDriverService());
      final locProv = LocationProvider();

      driverProv.setDriverProfileForTesting(
        DriverProfile.empty(userId: 'd_unverified').copyWith(
          isVerified: false,
        ),
      );

      await viewModel.checkAndAutoGoOnline(driverProv: driverProv, locProv: locProv);
      expect(driverProv.isOnline, isFalse);
    });

    test('checkAndAutoGoOnline transitions unverified driver with configured vehicle online when verification optional', () async {
      final storage = NativeStorageService();
      await storage.remove('driver_explicitly_offline');

      final viewModel = DriverViewModel();
      final driverProv = DriverProvider(firestoreService: FakeFirestoreDriverService());
      final locProv = LocationProvider();

      driverProv.setDriverProfileForTesting(
        DriverProfile.empty(userId: 'd_unverified_configured').copyWith(
          isVerified: false,
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'LEA-21-4567',
            color: 'White',
          ),
        ),
      );

      await viewModel.checkAndAutoGoOnline(driverProv: driverProv, locProv: locProv);
      expect(driverProv.isOnline, isTrue);
    });

    test('checkAndAutoGoOnline transitions verified driver with configured vehicle online', () async {
      final storage = NativeStorageService();
      await storage.remove('driver_explicitly_offline');

      final viewModel = DriverViewModel();
      final driverProv = DriverProvider(firestoreService: FakeFirestoreDriverService());
      final locProv = LocationProvider();

      driverProv.setDriverProfileForTesting(
        DriverProfile.empty(userId: 'd_verified').copyWith(
          isVerified: true,
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'LEA-21-4567',
            color: 'White',
          ),
        ),
      );

      await viewModel.checkAndAutoGoOnline(driverProv: driverProv, locProv: locProv);
      expect(driverProv.isOnline, isTrue);

      final explicitlyOffline = await storage.getBool('driver_explicitly_offline');
      expect(explicitlyOffline, isFalse);
    });

    test('checkAndAutoGoOnline respects explicit offline toggle', () async {
      final storage = NativeStorageService();
      await storage.setBool('driver_explicitly_offline', true);

      final viewModel = DriverViewModel();
      final driverProv = DriverProvider(firestoreService: FakeFirestoreDriverService());
      final locProv = LocationProvider();

      driverProv.setDriverProfileForTesting(
        DriverProfile.empty(userId: 'd_offline').copyWith(
          isVerified: true,
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'LEA-21-4567',
            color: 'White',
          ),
        ),
      );

      await viewModel.checkAndAutoGoOnline(driverProv: driverProv, locProv: locProv);
      expect(driverProv.isOnline, isFalse);
    });

    testWidgets('DriverStatusCredibilityDialog (Turning ON) renders details and pops true on Got It', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await DriverStatusCredibilityDialog.show(ctx, isGoingOnline: true);
                },
                child: const Text('Open ON Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open ON Dialog'));
      await tester.pumpAndSettle();

      expect(find.text("You're Online & Ready for Offers"), findsOneWidget);
      expect(find.textContaining('Works Even When Closed'), findsOneWidget);
      expect(find.textContaining('Battery-Smart Standby'), findsOneWidget);
      expect(find.textContaining('98% Earnings Guarantee'), findsOneWidget);
      expect(find.textContaining('Full Control'), findsOneWidget);
      expect(find.byKey(const Key('driver_credibility_got_it_btn')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('driver_credibility_got_it_btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('driver_credibility_got_it_btn')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text("You're Online & Ready for Offers"), findsNothing);
    });

    testWidgets('DriverStatusCredibilityDialog (Turning OFF) pops false on Stay Online', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await DriverStatusCredibilityDialog.show(ctx, isGoingOnline: false);
                },
                child: const Text('Open OFF Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open OFF Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Go Offline & Pause Offers?'), findsOneWidget);
      expect(find.textContaining('No Ride Alerts'), findsOneWidget);
      expect(find.textContaining('GPS Completely Stopped'), findsOneWidget);
      expect(find.textContaining('Manual Resume'), findsOneWidget);
      expect(find.byKey(const Key('driver_credibility_stay_online_btn')), findsOneWidget);
      expect(find.byKey(const Key('driver_credibility_confirm_offline_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('driver_credibility_stay_online_btn')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('Go Offline & Pause Offers?'), findsNothing);
    });

    testWidgets('DriverStatusCredibilityDialog (Turning OFF) pops true on Confirm Go Offline', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await DriverStatusCredibilityDialog.show(ctx, isGoingOnline: false);
                },
                child: const Text('Open OFF Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open OFF Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('driver_credibility_confirm_offline_btn')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('Go Offline & Pause Offers?'), findsNothing);
    });

    test('Confirm Go Offline executes toggleOnline while Stay Online cancels', () async {
      final viewModel = DriverViewModel();
      final driverProv = DriverProvider(firestoreService: FakeFirestoreDriverService());
      final locProv = LocationProvider();

      driverProv.setDriverProfileForTesting(
        DriverProfile.empty(userId: 'driver_active').copyWith(
          isVerified: true,
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            year: 2022,
            plate: 'LEA-21-4567',
            color: 'White',
          ),
        ),
      );

      // 1. Go Online
      await viewModel.toggleOnline(driverProv: driverProv, locProv: locProv, online: true);
      expect(driverProv.isOnline, isTrue);

      // 2. Simulate Stay Online (result == false): toggleOnline is NOT called
      Future<void> handleUserOfflineConfirmation(bool confirmed) async {
        if (confirmed) {
          await viewModel.toggleOnline(driverProv: driverProv, locProv: locProv, online: false);
        }
      }

      await handleUserOfflineConfirmation(false);
      expect(driverProv.isOnline, isTrue); // Remained online!

      // 3. Simulate Confirm Go Offline (result == true): toggleOnline is called
      await handleUserOfflineConfirmation(true);
      expect(driverProv.isOnline, isFalse); // Successfully went offline!
    });
  });
}
