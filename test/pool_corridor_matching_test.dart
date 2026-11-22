import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/presentation/view_models/driver_view_model.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('En-Route Dynamic Seat Pooling & Waypoints', () {
    test('RideModel supports parentPoolRideId, remainingSeats, and waypoints', () {
      final ride = RideModel(
        id: 'pool_ride_001',
        riderId: 'rider_a',
        pickup: const LocationPoint(latitude: 31.5204, longitude: 74.3587, address: 'Mall Road'),
        dropoff: const LocationPoint(latitude: 31.5820, longitude: 74.3294, address: 'Liberty'),
        offeredFare: 450.0,
        suggestedFare: 450.0,
        distanceKm: 8.5,
        durationMin: 22.0,
        pin: '4321',
        createdAt: DateTime.now(),
        vehicleType: 'car',
        bookedSeats: 1,
        remainingSeats: 3,
        parentPoolRideId: 'master_pool_999',
        waypoints: [
          {
            'rideId': 'pool_ride_001',
            'type': 'pickup',
            'lat': 31.5204,
            'lng': 74.3587,
            'address': 'Mall Road',
            'pin': '4321',
            'completed': false,
          },
          {
            'rideId': 'pool_ride_001',
            'type': 'dropoff',
            'lat': 31.5820,
            'lng': 74.3294,
            'address': 'Liberty',
            'pin': '4321',
            'completed': false,
          },
        ],
      );

      expect(ride.isPooled, isTrue);
      expect(ride.parentPoolRideId, 'master_pool_999');
      expect(ride.remainingSeats, 3);
      expect(ride.waypoints.length, 2);

      // Serialization and deserialization
      final map = ride.toMap();
      expect(map['parentPoolRideId'], 'master_pool_999');
      expect(map['remainingSeats'], 3);
      expect((map['waypoints'] as List).length, 2);

      final reconstructed = RideModel.fromMap(map, docId: 'pool_ride_001');
      expect(reconstructed.parentPoolRideId, 'master_pool_999');
      expect(reconstructed.remainingSeats, 3);
      expect(reconstructed.waypoints.length, 2);
      expect(reconstructed.waypoints[0]['pin'], '4321');
    });

    test('DriverViewModel waypoint progression and PIN verification', () async {
      final viewModel = DriverViewModel();

      final baseRide = RideModel(
        id: 'active_pool_master',
        riderId: 'rider_main',
        pickup: const LocationPoint(latitude: 31.50, longitude: 74.30, address: 'Stop 0'),
        dropoff: const LocationPoint(latitude: 31.60, longitude: 74.40, address: 'Final Destination'),
        offeredFare: 600.0,
        suggestedFare: 600.0,
        distanceKm: 12.0,
        durationMin: 30.0,
        pin: '1111',
        createdAt: DateTime.now(),
        status: RideStatus.inProgress,
        waypoints: [
          {
            'rideId': 'co_rider_leg',
            'type': 'pickup',
            'lat': 31.52,
            'lng': 74.32,
            'address': 'Co-Rider Pickup',
            'pin': '8888',
            'completed': false,
          },
          {
            'rideId': 'co_rider_leg',
            'type': 'dropoff',
            'lat': 31.58,
            'lng': 74.38,
            'address': 'Co-Rider Dropoff',
            'pin': '8888',
            'completed': false,
          },
        ],
      );

      final rideProv = RideProvider(initialRide: baseRide);
      final authProv = AuthProvider();
      final driverProv = DriverProvider();

      // Active waypoint should be index 0 (pickup)
      expect(viewModel.getActiveWaypointIndex(rideProv.currentRide), 0);
      final activeWaypoint = viewModel.getActiveWaypoint(rideProv.currentRide);
      expect(activeWaypoint!['type'], 'pickup');
      expect(activeWaypoint['address'], 'Co-Rider Pickup');

      // Attempt verification with incorrect PIN
      final failResult = await viewModel.verifyAndCompleteWaypoint(
        rideProv: rideProv,
        enteredPin: '0000',
        authProv: authProv,
        driverProv: driverProv,
      );
      expect(failResult, isFalse);
      expect(viewModel.pinErrorMessage, isNotNull);
      expect(viewModel.getActiveWaypointIndex(rideProv.currentRide), 0);

      // Attempt verification with correct PIN '8888'
      final successResult = await viewModel.verifyAndCompleteWaypoint(
        rideProv: rideProv,
        enteredPin: '8888',
        authProv: authProv,
        driverProv: driverProv,
      );
      expect(successResult, isTrue);
      expect(viewModel.pinErrorMessage, isNull);

      // Now active waypoint should advance to index 1 (dropoff)
      expect(viewModel.getActiveWaypointIndex(rideProv.currentRide), 1);
      final nextWaypoint = viewModel.getActiveWaypoint(rideProv.currentRide);
      expect(nextWaypoint!['type'], 'dropoff');

      // Complete the final dropoff
      final dropoffSuccess = await viewModel.verifyAndCompleteWaypoint(
        rideProv: rideProv,
        enteredPin: '',
        authProv: authProv,
        driverProv: driverProv,
      );
      expect(dropoffSuccess, isTrue);
      // All waypoints completed, so active waypoint is now -1
      expect(viewModel.getActiveWaypointIndex(rideProv.currentRide), -1);
    });
  });
}
