import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/services/firestore/firestore_driver_service.dart';
import 'package:swiftride/services/native/native_channel_constants.dart';
import 'package:swiftride/services/native/native_storage_service.dart';

class TestFirestoreDriverService implements FirestoreDriverService {
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

  final List<MethodCall> locationChannelCalls = <MethodCall>[];

  setUp(() {
    locationChannelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(NativeChannelConstants.locationChannel),
      (MethodCall call) async {
        locationChannelCalls.add(call);
        return true;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(NativeChannelConstants.locationChannel),
      null,
    );
  });

  group('NativeLocationService MethodChannel Integration Tests', () {
    test('toggleOnline invokes setDriverOnlineState on native locationChannel', () async {
      final storage = NativeStorageService();
      await storage.remove('driver_explicitly_offline');

      final viewModel = DriverViewModel();
      final driverProv = DriverProvider(firestoreService: TestFirestoreDriverService());
      final locProv = LocationProvider();

      driverProv.setDriverProfileForTesting(
        DriverProfile.empty(userId: 'driver_test_99').copyWith(
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

      final err = await viewModel.toggleOnline(
        driverProv: driverProv,
        locProv: locProv,
        online: true,
      );

      expect(err, isNull);
      expect(driverProv.isOnline, isTrue);

      final onlineCalls = locationChannelCalls.where(
        (c) => c.method == NativeChannelConstants.methodSetDriverOnlineState,
      ).toList();

      expect(onlineCalls, isNotEmpty);
      final lastCall = onlineCalls.last;
      expect(lastCall.arguments['isOnline'], isTrue);
      expect(lastCall.arguments['driverUid'], equals('driver_test_99'));
    });

    test('toggleOnline with false sets isOnline to false in native call', () async {
      final viewModel = DriverViewModel();
      final driverProv = DriverProvider(firestoreService: TestFirestoreDriverService());
      final locProv = LocationProvider();

      driverProv.setDriverProfileForTesting(
        DriverProfile.empty(userId: 'driver_test_99').copyWith(
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

      await viewModel.toggleOnline(
        driverProv: driverProv,
        locProv: locProv,
        online: false,
      );

      final offlineCalls = locationChannelCalls.where(
        (c) => c.method == NativeChannelConstants.methodSetDriverOnlineState,
      ).toList();

      expect(offlineCalls, isNotEmpty);
      expect(offlineCalls.last.arguments['isOnline'], isFalse);
    });
  });
}
