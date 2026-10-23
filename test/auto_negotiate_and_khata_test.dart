import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/location_point_model.dart';
import 'package:swiftride/domain/models/ride_model.dart';
import 'package:swiftride/domain/models/ride_offer_model.dart';
import 'package:swiftride/domain/models/ride_status.dart';
import 'package:swiftride/domain/models/driver_khata_model.dart';
import 'package:swiftride/providers/ride_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto-Negotiate Bot & Driver Khata Tests', () {
    test('RideProvider auto-accepts offers at or below maxAutoAcceptFare and ignores offers above it', () async {
      final initialRide = RideModel(
        id: 'test_ride_123',
        riderId: 'rider_99',
        pickup: const LocationPoint(latitude: 31.5204, longitude: 74.3587, address: 'Lahore Cantt'),
        dropoff: const LocationPoint(latitude: 31.5820, longitude: 74.3294, address: 'Gulberg III'),
        offeredFare: 350.0,
        suggestedFare: 350.0,
        distanceKm: 8.5,
        durationMin: 22.0,
        pin: '1234',
        createdAt: DateTime.now(),
        isAutoNegotiateEnabled: true,
        maxAutoAcceptFare: 400.0,
        status: RideStatus.requested,
      );

      final rideProv = RideProvider(initialRide: initialRide);

      expect(rideProv.currentRide?.isAutoNegotiateEnabled, isTrue);
      expect(rideProv.currentRide?.maxAutoAcceptFare, 400.0);
      expect(rideProv.currentRide?.status, RideStatus.requested);

      // 1. Offer exceeding budget ceiling (450 > 400) -> Must be ignored
      final highOffer = RideOffer(
        id: 'offer_high',
        rideId: 'test_ride_123',
        driverId: 'driver_expensive',
        driverName: 'Aslam',
        counterFare: 450.0,
        etaMinutes: 5,
        vehicleSummary: 'Honda Civic (White)',
        driverRating: 4.8,
        createdAt: DateTime.now(),
      );

      rideProv.handleIncomingOffers([highOffer]);

      // Assert offer was not auto-accepted
      expect(rideProv.currentRide?.status, RideStatus.requested);
      expect(rideProv.currentRide?.driverId, isNull);
      expect(rideProv.autoNegotiateBanner, isNull);

      // 2. Offer within budget ceiling (380 <= 400) -> Must auto-accept instantly
      final fairOffer = RideOffer(
        id: 'offer_fair',
        rideId: 'test_ride_123',
        driverId: 'driver_hamza',
        driverName: 'Hamza',
        counterFare: 380.0,
        etaMinutes: 3,
        vehicleSummary: 'Toyota Corolla (Silver)',
        driverRating: 4.9,
        createdAt: DateTime.now(),
      );

      rideProv.handleIncomingOffers([fairOffer]);

      // Allow any microtasks to settle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(rideProv.currentRide?.driverId, 'driver_hamza');
      expect(rideProv.currentRide?.acceptedFare, 380.0);
      expect(rideProv.currentRide?.status, RideStatus.accepted);
      expect(
        rideProv.autoNegotiateBanner,
        contains("Auto-Negotiate: Accepted Captain Hamza's offer of PKR 380!"),
      );

      rideProv.dispose();
    });

    test('DriverDailyKhata math correctly subtracts live fuel and maintenance wear to yield net profit', () {
      final now = DateTime.now();
      var khata = DriverDailyKhata(date: now);

      expect(khata.completedTrips, 0);
      expect(khata.totalGrossCashCollected, 0.0);
      expect(khata.netCashProfit, 0.0);

      // Add Trip 1: Fare PKR 1000, Fuel PKR 300, Maintenance PKR 100
      khata = khata.addTrip(
        cashCollected: 1000.0,
        fuelExpense: 300.0,
        maintenanceReserve: 100.0,
      );

      expect(khata.completedTrips, 1);
      expect(khata.totalGrossCashCollected, 1000.0);
      expect(khata.totalFuelExpense, 300.0);
      expect(khata.totalMaintenanceReserve, 100.0);
      // Net Profit: 1000 - (300 + 100) = 600
      expect(khata.netCashProfit, 600.0);

      // Add Trip 2: Fare PKR 500, Fuel PKR 150, Maintenance PKR 50
      khata = khata.addTrip(
        cashCollected: 500.0,
        fuelExpense: 150.0,
        maintenanceReserve: 50.0,
      );

      expect(khata.completedTrips, 2);
      expect(khata.totalGrossCashCollected, 1500.0);
      expect(khata.totalFuelExpense, 450.0);
      expect(khata.totalMaintenanceReserve, 150.0);
      // Net Profit: 1500 - (450 + 150) = 900
      expect(khata.netCashProfit, 900.0);

      // Verify serialization round-trip
      final map = khata.toMap();
      final restored = DriverDailyKhata.fromMap(map);
      expect(restored.completedTrips, 2);
      expect(restored.totalGrossCashCollected, 1500.0);
      expect(restored.netCashProfit, 900.0);
    });

    test('Exact change assistant calculates correct change for PKR 500 and PKR 1000 cash notes', () {
      const fare = 320.0;

      // Passenger hands over PKR 500 note
      const cashReceived500 = 500.0;
      final changeDue500 = (cashReceived500 - fare).clamp(0.0, 999999.0);
      expect(changeDue500, 180.0);

      double calculateEffectiveCash(double received, double tripFare, bool isTipped) {
        return isTipped ? received : tripFare;
      }

      // If rider allows driver to keep change as tip:
      expect(calculateEffectiveCash(cashReceived500, fare, true), 500.0);

      // If rider takes back change:
      expect(calculateEffectiveCash(cashReceived500, fare, false), 320.0);

      // Passenger hands over PKR 1000 note
      const cashReceived1000 = 1000.0;
      final changeDue1000 = (cashReceived1000 - fare).clamp(0.0, 999999.0);
      expect(changeDue1000, 680.0);

      // Passenger hands over exact change
      const cashReceivedExact = 320.0;
      final changeDueExact = (cashReceivedExact - fare).clamp(0.0, 999999.0);
      expect(changeDueExact, 0.0);
    });
  });
}
