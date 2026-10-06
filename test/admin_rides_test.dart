import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/providers/admin_provider.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Admin console ride log', () {
    test('starts empty with no error', () {
      final provider = AdminProvider();

      expect(provider.platformRides, isEmpty);
      expect(provider.ridesError, isNull);
      expect(provider.isLoadingRides, isFalse);

      provider.dispose();
    });

    test('reports a connection error rather than an empty platform', () async {
      final provider = AdminProvider();

      await provider.loadPlatformRides();

      // The console's "Live Ride Activity" panel used to be fed from the signed-in
      // admin's own ride history, so it read "no rides recorded yet" on a busy
      // platform. With no backend it must say so, not claim the platform is idle.
      expect(provider.ridesError, isNotNull);
      expect(provider.isLoadingRides, isFalse);

      provider.dispose();
    });
  });

  group('FirestoreRideService.fetchAdminRides', () {
    test('fails honestly without Firebase', () async {
      final page = await FirestoreRideService().fetchAdminRides();

      expect(page.rides, isEmpty);
      expect(page.error, isNotNull);
    });
  });
}
