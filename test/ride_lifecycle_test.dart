import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_offer_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/services/firestore/firestore_ride_service.dart';

void main() {
  final service = FirestoreRideService();

  int seq = 0;
  String nextId(String prefix) => '${prefix}_${seq++}';

  RideModel newRide({String riderId = 'rider_1', String pin = '4321'}) => RideModel(
        id: nextId('ride'),
        riderId: riderId,
        pickup: const LocationPoint(latitude: 33.70, longitude: 73.05, address: 'A'),
        dropoff: const LocationPoint(latitude: 33.56, longitude: 72.85, address: 'B'),
        offeredFare: 500,
        suggestedFare: 520,
        distanceKm: 5.2,
        durationMin: 12,
        pin: pin,
        createdAt: DateTime.now(),
      );

  group('Ride lifecycle handshake', () {
    test('closes end to end: request → bid → accept → arrive → PIN → complete', () async {
      final ride = newRide();
      await service.createRide(ride);

      var current = await service.getRide(ride.id);
      expect(current!.status, RideStatus.requested);
      expect(current.driverId, isNull);

      // A driver bids; the rider's offer stream reads these back.
      final offer = RideOffer(
        id: nextId('offer'),
        rideId: ride.id,
        driverId: 'driver_1',
        driverName: 'Driver One',
        counterFare: 520,
        etaMinutes: 4,
        vehicleSummary: 'White Toyota Corolla',
        createdAt: DateTime.now(),
      );
      await service.submitOffer(offer);

      final offers = await service.streamOffersForRide(ride.id).first;
      expect(offers, hasLength(1));
      expect(offers.first.driverId, 'driver_1');

      // Rider accepts — this is what assigns the driver and moves the trip on.
      await service.acceptOffer(ride.id, offer);
      current = await service.getRide(ride.id);
      expect(current!.status, RideStatus.accepted);
      expect(current.driverId, 'driver_1');
      expect(current.acceptedFare, 520);

      await service.markDriverArrived(ride.id);
      current = await service.getRide(ride.id);
      expect(current!.status, RideStatus.driverArrived);

      // The PIN handshake must reject a wrong code and accept the real one.
      expect(await service.verifyPinAndStartTrip(ride.id, '0000'), isFalse);
      expect(await service.verifyPinAndStartTrip(ride.id, '4321'), isTrue);

      current = await service.getRide(ride.id);
      expect(current!.status, RideStatus.inProgress);

      await service.completeTrip(ride.id);
      current = await service.getRide(ride.id);
      expect(current!.status, RideStatus.completed);

      // Settlement is owned by the payment flow — completing a trip must never
      // record money as collected.
      expect(current.paymentStatus, isNot(equals('paid')));
    });

    test('a wrong PIN leaves the trip in DRIVER_ARRIVED', () async {
      final ride = newRide(pin: '9999');
      await service.createRide(ride);
      await service.markDriverArrived(ride.id);

      expect(await service.verifyPinAndStartTrip(ride.id, '1234'), isFalse);

      final current = await service.getRide(ride.id);
      expect(current!.status, RideStatus.driverArrived);
    });
  });

  group('RideProvider.resumeActiveRide', () {
    test('restores a trip that is still in progress', () async {
      final ride = newRide(riderId: 'rider_resume');
      await service.createRide(ride);
      await service.markDriverArrived(ride.id);

      final found = await service.findActiveRide(userId: 'rider_resume', asDriver: false);

      expect(found, isNotNull);
      expect(found!.id, ride.id);
    });

    test('does not resume a completed trip', () async {
      final ride = newRide(riderId: 'rider_done');
      await service.createRide(ride);
      await service.markDriverArrived(ride.id);
      await service.verifyPinAndStartTrip(ride.id, '4321');
      await service.completeTrip(ride.id);

      final found = await service.findActiveRide(userId: 'rider_done', asDriver: false);

      expect(found, isNull);
    });

    test('returns null when the user has no trips', () async {
      final found = await service.findActiveRide(userId: 'nobody', asDriver: false);
      expect(found, isNull);
    });
  });
}
