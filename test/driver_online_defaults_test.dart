import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
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

    test('checkAndAutoGoOnline keeps unverified driver offline', () async {
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
  });
}
