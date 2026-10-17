import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/presentation/rider/address_search_screen.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Map Location Picker Tests', () {
    test('RiderViewModel pin picker does not mutate pickup until confirmed', () async {
      final vm = RiderViewModel();
      const initialPickup = LocationPoint(
        latitude: 31.2785,
        longitude: 72.3317,
        address: 'Initial Spot, Jhang',
      );
      vm.setPickup(initialPickup);
      expect(vm.pickupLocation?.address, equals('Initial Spot, Jhang'));

      // Start pin picker
      vm.startPinPicker(isPickup: true);
      expect(vm.isPinMode, isTrue);
      expect(vm.isPinningPickup, isTrue);
      expect(vm.tempPinLocation?.latitude, equals(31.2785));

      // Drag map / camera move to new coordinates
      await vm.updatePinnedCoordinates(31.2900, 72.3400);

      // Verify pickupLocation is STILL the initial spot (not mutated by scrolling/panning)
      expect(vm.pickupLocation?.latitude, equals(31.2785));
      expect(vm.pickupLocation?.address, equals('Initial Spot, Jhang'));
      // Only tempPinLocation is updated
      expect(vm.tempPinLocation?.latitude, equals(31.2900));

      // User explicitly confirms location
      vm.confirmPinLocation();
      expect(vm.isPinMode, isFalse);
      expect(vm.pickupLocation?.latitude, equals(31.2900));
    });

    test('RiderViewModel canceling pin picker preserves original location', () async {
      final vm = RiderViewModel();
      const initialPickup = LocationPoint(
        latitude: 31.2785,
        longitude: 72.3317,
        address: 'Initial Spot, Jhang',
      );
      vm.setPickup(initialPickup);

      vm.startPinPicker(isPickup: true);
      await vm.updatePinnedCoordinates(31.3500, 72.4000);

      // Cancel pin picker
      vm.cancelPinPicker();
      expect(vm.isPinMode, isFalse);
      expect(vm.tempPinLocation, isNull);
      // Original pickup is safely preserved
      expect(vm.pickupLocation?.latitude, equals(31.2785));
      expect(vm.pickupLocation?.address, equals('Initial Spot, Jhang'));
    });

    testWidgets('AddressSearchScreen displays Choose on Map and pops with __CHOOSE_ON_MAP__', (tester) async {
      LocationPoint? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedResult = await Navigator.of(context).push<LocationPoint>(
                  MaterialPageRoute(
                    builder: (_) => const AddressSearchScreen(title: 'Set Pickup Location'),
                  ),
                );
              },
              child: const Text('Open Search'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Search'));
      await tester.pumpAndSettle();

      // Verify "Choose on Map" tile is present
      expect(find.text('Choose on Map'), findsOneWidget);
      expect(find.text('Pinpoint exact spot with interactive map pin'), findsOneWidget);

      // Tap "Choose on Map"
      await tester.tap(find.text('Choose on Map'));
      await tester.pumpAndSettle();

      // Verify popped result signals map picker
      expect(selectedResult, isNotNull);
      expect(selectedResult!.address, equals('__CHOOSE_ON_MAP__'));
    });
  });

  group('OTP and Account Creation Tests', () {
    test('AuthService and AuthProvider verify test OTP and create account', () async {
      final authProvider = AuthProvider();

      String? verificationId;
      await authProvider.sendOtp(
        phoneNumber: '+923000000000',
        onCodeSent: (vId, _) => verificationId = vId,
        onError: (e) => fail('sendOtp failed: $e'),
      );

      expect(verificationId, isNotNull);

      // Verify test OTP 123456
      bool verifySuccess = false;
      await authProvider.verifyOtp(
        smsCode: '123456',
        phoneNumber: '+923000000000',
        fullName: 'Test Driver',
        onSuccess: () => verifySuccess = true,
        onError: (err) => fail('verifyOtp failed: $err'),
      );

      expect(verifySuccess, isTrue);
      expect(authProvider.currentUser.fullName, equals('Test Driver'));
      expect(authProvider.currentUser.phone, equals('+923000000000'));
      expect(authProvider.currentUser.id, isNotEmpty);
    });
  });
}
