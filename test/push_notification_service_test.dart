import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/routing/app_router.dart';
import 'package:swiftride/services/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushNotificationService', () {
    test('singleton instance is non-null and holds valid web VAPID key', () {
      final service = PushNotificationService.instance;
      expect(service, isNotNull);
      expect(
        PushNotificationService.webVapidKey,
        'BIkT-JAqg_eWAUN0U_CVemQ3GmTWuLrrdO6KRmZ1pPLQrAoFqJErAIu4L6HS97dVR25FStVLuEItda4xUXnzndk',
      );
    });

    test('initialize runs safely when Firebase is uninitialized in test environment', () async {
      final service = PushNotificationService.instance;
      // Should not throw
      await service.initialize(onNotificationTap: (data) {});
      expect(service, isNotNull);
    });

    test('removeCurrentTokenOnLogout runs safely without active session', () async {
      final service = PushNotificationService.instance;
      // Should not throw
      await service.removeCurrentTokenOnLogout();
      expect(service, isNotNull);
    });

    test('AppRouter.handleNotificationTap routes dispatch payloads gracefully', () {
      final testPayloads = [
        {'type': 'NEW_RIDE_REQUEST', 'rideId': 'r1'},
        {'type': 'COUNTER_OFFER', 'rideId': 'r2'},
        {'type': 'OFFER_ACCEPTED', 'rideId': 'r3'},
        {'type': 'DRIVER_ARRIVED', 'rideId': 'r4'},
        {'type': 'SAFETY_ALERT', 'rideId': 'r5'},
        {'type': 'SOS', 'rideId': 'r6'},
      ];

      for (final payload in testPayloads) {
        expect(() => AppRouter.handleNotificationTap(payload), returnsNormally);
      }
    });
  });
}
