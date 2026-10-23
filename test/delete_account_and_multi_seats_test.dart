import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/domain/models/vehicle_type.dart';
import 'package:swiftride/presentation/view_models/rider_view_model.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/services/firestore/firestore_user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Account Deletion Tests (Apple Guideline 5.1.1(v))', () {
    test('FirestoreUserService.deleteUser removes user document and clears memory cache', () async {
      final user = AppUser(
        id: 'test_delete_user_123',
        fullName: 'Delete Test User',
        phone: '+923001234567',
        role: UserRole.rider,
        rating: 5.0,
        totalRides: 2,
        createdAt: DateTime.now(),
      );

      final service = FirestoreUserService();
      await service.saveUser(user);

      // Verify cached
      final retrieved = await service.getUser(user.id);
      expect(retrieved, isNotNull);
      expect(retrieved?.id, equals(user.id));

      // Delete user
      final success = await service.deleteUser(user.id);
      expect(success, isTrue);

      // Verify removed
      final afterDelete = await service.getUser(user.id);
      expect(afterDelete, isNull);
    });

    test('AuthProvider.deleteAccount resets user to guest and clears credentials', () async {
      final auth = AuthProvider(
        initialUser: AppUser(
          id: 'auth_delete_user_456',
          fullName: 'Alice Persona',
          phone: '+923331112233',
          role: UserRole.rider,
          rating: 4.9,
          totalRides: 5,
          createdAt: DateTime.now(),
        ),
      );

      expect(auth.currentUser.fullName, equals('Alice Persona'));

      final success = await auth.deleteAccount();
      expect(success, isTrue);
      expect(auth.currentUser.fullName, equals('Guest User'));
      expect(auth.activeRole, equals(UserRole.rider));
    });
  });

  group('Multiple Seats / Passengers Selection Tests', () {
    test('RiderViewModel allows selecting multiple seats up to vehicle capacity', () {
      final vm = RiderViewModel();

      // Default is Car (capacity 4)
      expect(vm.selectedVehicleType, equals(VehicleType.car));
      expect(vm.bookedSeats, equals(1));

      // User carrying 3 people along -> select 3 seats
      vm.setBookedSeats(3);
      expect(vm.bookedSeats, equals(3));

      // User carrying family -> select 4 seats
      vm.setBookedSeats(4);
      expect(vm.bookedSeats, equals(4));

      // Clamping exceeds vehicle seats
      vm.setBookedSeats(10);
      expect(vm.bookedSeats, equals(4));

      // Switch to Bike (capacity 1) -> auto clamped to 1
      vm.selectVehicleType(VehicleType.bike);
      expect(vm.selectedVehicleType, equals(VehicleType.bike));
      expect(vm.bookedSeats, equals(1));

      // Switching to Rikshaw (capacity 2)
      vm.selectVehicleType(VehicleType.rikshaw);
      expect(vm.selectedVehicleType, equals(VehicleType.rikshaw));
      vm.setBookedSeats(2);
      expect(vm.bookedSeats, equals(2));
    });

    test('RideModel persists and restores bookedSeats for multiple passengers', () {
      final ride = RideModel(
        id: 'ride_multi_seat_789',
        riderId: 'rider_abc',
        status: RideStatus.requested,
        pickup: const LocationPoint(
          latitude: 31.5204,
          longitude: 74.3587,
          address: 'Gulberg III, Lahore',
        ),
        dropoff: const LocationPoint(
          latitude: 31.4697,
          longitude: 74.4082,
          address: 'DHA Phase 5, Lahore',
        ),
        offeredFare: 750.0,
        suggestedFare: 700.0,
        distanceKm: 12.5,
        durationMin: 25.0,
        vehicleType: 'car',
        bookedSeats: 3, // Carrying 3 passengers along
        pin: '1234',
        createdAt: DateTime.now(),
      );

      final map = ride.toMap();
      expect(map['bookedSeats'], equals(3));

      final restored = RideModel.fromMap(map, docId: 'ride_multi_seat_789');
      expect(restored.bookedSeats, equals(3));
      expect(restored.id, equals('ride_multi_seat_789'));
    });
  });
}
