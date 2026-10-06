import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';

void main() {
  group('RideHistoryPage', () {
    test('distinguishes an empty history from a failed load', () {
      // The UI must be able to tell "you have no rides yet" apart from
      // "we could not reach the server" — the old code returned an empty list
      // for both, so a network failure looked like an empty history.
      const genuinelyEmpty = RideHistoryPage(rides: []);
      expect(genuinelyEmpty.rides, isEmpty);
      expect(genuinelyEmpty.error, isNull);
      expect(genuinelyEmpty.hasMore, isFalse);

      const failed = RideHistoryPage(rides: [], error: 'We could not load your ride history.');
      expect(failed.rides, isEmpty);
      expect(failed.error, isNotNull);
    });
  });

  group('FirestoreRideService.fetchRideHistoryPage', () {
    test('returns an honest empty page when there is no backend', () async {
      final page = await FirestoreRideService().fetchRideHistoryPage(riderId: 'rider_test');

      expect(page.rides, isEmpty);
      expect(page.error, isNull);
      expect(page.hasMore, isFalse);
      expect(page.lastDocument, isNull);
    });

    test('reports hasMore false so pagination terminates', () async {
      final page = await FirestoreRideService().fetchRideHistoryPage(
        riderId: 'rider_test',
        limit: 20,
      );

      // A short page must never advertise more pages, or the "load older rides"
      // control would spin forever.
      expect(page.hasMore, isFalse);
    });
  });
}
