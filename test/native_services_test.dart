import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/native/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Services Zero-Dependency Suite', () {
    test('NativeStorageService performs persistent key-value caching', () async {
      final storage = NativeStorageService();

      await storage.setString('test_key', 'test_value');
      final val = await storage.getString('test_key');
      expect(val, equals('test_value'));

      await storage.setBool('is_driver', true);
      final isDriver = await storage.getBool('is_driver');
      expect(isDriver, isTrue);

      await storage.setInt('ride_count', 42);
      final count = await storage.getInt('ride_count');
      expect(count, equals(42));

      await storage.setDouble('base_fare', 150.0);
      final fare = await storage.getDouble('base_fare');
      expect(fare, equals(150.0));

      await storage.remove('test_key');
      final removed = await storage.getString('test_key');
      expect(removed, isNull);

      await storage.clear();
      final clearedBool = await storage.getBool('is_driver');
      expect(clearedBool, isNull);
    });

    test('NativeNotificationService triggers notifications cleanly without crashing', () async {
      final notif = NativeNotificationService();

      final granted = await notif.requestPermissions();
      expect(granted, isTrue);

      final shown = await notif.showNotification(
        id: 1,
        title: 'Driver Arrived',
        body: 'Toyota Camry is at pickup point.',
      );
      expect(shown, isTrue);

      final cancelled = await notif.cancelNotification(1);
      expect(cancelled, isTrue);

      final allCancelled = await notif.cancelAllNotifications();
      expect(allCancelled, isTrue);
    });

    test('NativeLauncherService handles dialer, SMS, directions, and URLs safely', () async {
      final launcher = NativeLauncherService();

      final dialed = await launcher.launchDialer('+92 300 1234567');
      expect(dialed, isTrue);

      final sms = await launcher.launchSms('+92 300 1234567', message: 'I have arrived');
      expect(sms, isTrue);

      final url = await launcher.launchUrl('https://swiftride.app');
      expect(url, isTrue);

      final nav = await launcher.launchMapsDirections(
        destinationLat: 33.7128,
        destinationLng: 73.0642,
      );
      expect(nav, isTrue);
    });

    test('NativeConnectivityService evaluates network connectivity', () async {
      final connectivity = NativeConnectivityService();

      final status = await connectivity.getConnectivityStatus();
      expect(status, isNotNull);

      final connected = await connectivity.isConnected();
      expect(connected, isTrue);
    });

    test('NativeAudioService triggers voice prompts and alarm tones safely', () async {
      final audio = NativeAudioService();

      final spoken = await audio.speak('Driver accepted your ride request.');
      expect(spoken, isTrue);

      final tone = await audio.playAlertTone('siren');
      expect(tone, isTrue);

      final stopped = await audio.stop();
      expect(stopped, isTrue);
    });

    test('NativeDeviceService fetches hardware and release version telemetry', () async {
      final device = NativeDeviceService();

      final battery = await device.getBatteryLevel();
      expect(battery, greaterThanOrEqualTo(0));

      final info = await device.getDeviceInfo();
      expect(info, contains('model'));

      final version = await device.getAppVersion();
      expect(version, isNotEmpty);
    });

    test('NativeMapController operates map channel operations safely', () async {
      final mapCtrl = NativeMapController();

      final camera = await mapCtrl.animateCamera(latitude: 33.6844, longitude: 73.0479);
      expect(camera, isTrue);

      final marker = await mapCtrl.addMarker(
        markerId: 'pickup_1',
        latitude: 33.6844,
        longitude: 73.0479,
        title: 'Pickup Location',
      );
      expect(marker, isTrue);

      final cleared = await mapCtrl.clearMarkers();
      expect(cleared, isTrue);
    });
  });
}
