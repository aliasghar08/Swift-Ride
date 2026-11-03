import 'dart:math' as math;
import 'native_map_service.dart';
import '../core/utils/distance_calculator.dart';
import '../domain/models/ride_model.dart';
import '../domain/models/vehicle_type.dart';

/// Represents a candidate ride along an active driver's route corridor.
class EnRouteMatch {
  final RideModel ride;
  final double detourKm;
  final double extraPetrolCost;
  final double netProfitBoost;
  final double pickupDistanceToCorridorKm;
  final double dropoffDistanceToCorridorKm;
  final String efficiencySummary;

  const EnRouteMatch({
    required this.ride,
    required this.detourKm,
    required this.extraPetrolCost,
    required this.netProfitBoost,
    required this.pickupDistanceToCorridorKm,
    required this.dropoffDistanceToCorridorKm,
    required this.efficiencySummary,
  });
}

/// Service that computes route corridor proximity and evaluates whether a
/// ride request can be picked up along an active driver's existing journey
/// without burning significant extra petrol.
class RouteCorridorService {
  /// Maximum allowable detour distance from the active route (in km).
  static const double maxPickupDetourKm = 1.8;
  static const double maxDropoffDetourKm = 2.2;
  static const double maxTotalDetourKm = 3.0;

  /// Default fuel constants in Pakistan (PKR 275/L petrol, ~14 km/L for 1.0L-1.3L city cars).
  static const double defaultFuelPricePkr = 275.0;
  static const double defaultKmPerLiter = 14.0;
  static const double swiftRideCommission = 0.02; // 2% platform fee

  /// Calculates the shortest perpendicular distance (in km) from a point to a line segment.
  static double distanceToSegment(
    LatLng point,
    LatLng start,
    LatLng end,
  ) {
    final double l2 = math.pow(end.latitude - start.latitude, 2) +
        math.pow(end.longitude - start.longitude, 2) as double;

    if (l2 == 0) {
      return DistanceCalculator.haversineDistance(
        point.latitude,
        point.longitude,
        start.latitude,
        start.longitude,
      );
    }

    // Projection scalar t onto segment [0, 1]
    final double t = math.max(
      0.0,
      math.min(
        1.0,
        ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
                (point.longitude - start.longitude) * (end.longitude - start.longitude)) /
            l2,
      ),
    );

    final double projLat = start.latitude + t * (end.latitude - start.latitude);
    final double projLng = start.longitude + t * (end.longitude - start.longitude);

    return DistanceCalculator.haversineDistance(
      point.latitude,
      point.longitude,
      projLat,
      projLng,
    );
  }

  /// Calculates the minimum perpendicular distance from a target coordinate to
  /// any segment of a route polyline.
  static double minDistanceToPolyline(
    LatLng target,
    List<LatLng> polylinePoints,
  ) {
    if (polylinePoints.isEmpty) return double.infinity;
    if (polylinePoints.length == 1) {
      return DistanceCalculator.haversineDistance(
        target.latitude,
        target.longitude,
        polylinePoints.first.latitude,
        polylinePoints.first.longitude,
      );
    }

    double minDistance = double.infinity;
    for (int i = 0; i < polylinePoints.length - 1; i++) {
      final d = distanceToSegment(
        target,
        polylinePoints[i],
        polylinePoints[i + 1],
      );
      if (d < minDistance) {
        minDistance = d;
      }
    }
    return minDistance;
  }

  /// Evaluates whether a candidate ride request is along the active route corridor.
  ///
  /// Returns [EnRouteMatch] if the pickup and dropoff lie within minimal detour limits
  /// and the vehicle has enough empty seats, or null if it causes significant petrol burn.
  static EnRouteMatch? evaluateCandidate({
    required RideModel activeRide,
    required List<LatLng> activeRoutePoints,
    required RideModel candidateRide,
    double fuelPricePkr = defaultFuelPricePkr,
    double kmPerLiter = defaultKmPerLiter,
  }) {
    // 0. Shared ride corridor is strictly for cars
    if (VehicleTypeX.fromString(activeRide.vehicleType) != VehicleType.car ||
        VehicleTypeX.fromString(candidateRide.vehicleType) != VehicleType.car) {
      return null;
    }

    // 1. Must have empty seats remaining
    if (candidateRide.bookedSeats > activeRide.emptySeats) {
      return null;
    }

    // 2. Candidate cannot be the active ride itself
    if (candidateRide.id == activeRide.id) {
      return null;
    }

    // Fallback if route points are empty: construct straight line between pickup and dropoff
    final points = activeRoutePoints.isNotEmpty
        ? activeRoutePoints
        : [
            LatLng(activeRide.pickup.latitude, activeRide.pickup.longitude),
            LatLng(activeRide.dropoff.latitude, activeRide.dropoff.longitude),
          ];

    final candidatePickup = LatLng(
      candidateRide.pickup.latitude,
      candidateRide.pickup.longitude,
    );
    final candidateDropoff = LatLng(
      candidateRide.dropoff.latitude,
      candidateRide.dropoff.longitude,
    );

    // 3. Proximity to route corridor
    final pickupDistKm = minDistanceToPolyline(candidatePickup, points);
    if (pickupDistKm > maxPickupDetourKm) {
      return null;
    }

    final dropoffDistKm = minDistanceToPolyline(candidateDropoff, points);
    if (dropoffDistKm > maxDropoffDetourKm) {
      return null;
    }

    // 4. Detour estimation (round-trip deviation to road)
    final detourKm = (pickupDistKm * 1.3) + (dropoffDistKm * 1.3);
    if (detourKm > maxTotalDetourKm) {
      return null;
    }

    // 5. Fuel cost of the detour
    final double fuelCostPerKm = fuelPricePkr / kmPerLiter;
    final double extraPetrolCost = (detourKm * fuelCostPerKm * 10).round() / 10.0;

    // 6. Net profit calculation after 2% platform commission
    final double offeredFare = candidateRide.offeredFare;
    final double driverGrossFare = offeredFare * (1.0 - swiftRideCommission);
    final double netProfitBoost = ((driverGrossFare - extraPetrolCost) * 10).round() / 10.0;

    // If net profit is not positive, it's not economically viable for the driver
    if (netProfitBoost <= 0) {
      return null;
    }

    return EnRouteMatch(
      ride: candidateRide,
      detourKm: (detourKm * 10).round() / 10.0,
      extraPetrolCost: extraPetrolCost,
      netProfitBoost: netProfitBoost,
      pickupDistanceToCorridorKm: (pickupDistKm * 10).round() / 10.0,
      dropoffDistanceToCorridorKm: (dropoffDistKm * 10).round() / 10.0,
      efficiencySummary:
          '+${detourKm.toStringAsFixed(1)} km detour • ~PKR ${extraPetrolCost.toInt()} petrol • +PKR ${netProfitBoost.toInt()} net profit',
    );
  }

  /// Filters a list of open requests to find all en-route matches along the active trip.
  static List<EnRouteMatch> findEnRouteMatches({
    required RideModel activeRide,
    required List<LatLng> activeRoutePoints,
    required List<RideModel> candidateRides,
    double fuelPricePkr = defaultFuelPricePkr,
    double kmPerLiter = defaultKmPerLiter,
  }) {
    // Shared ride corridor is strictly for cars
    if (VehicleTypeX.fromString(activeRide.vehicleType) != VehicleType.car ||
        !activeRide.hasEmptySeats ||
        activeRide.emptySeats <= 0) {
      return const [];
    }

    final matches = <EnRouteMatch>[];
    for (final candidate in candidateRides) {
      final match = evaluateCandidate(
        activeRide: activeRide,
        activeRoutePoints: activeRoutePoints,
        candidateRide: candidate,
        fuelPricePkr: fuelPricePkr,
        kmPerLiter: kmPerLiter,
      );
      if (match != null) {
        matches.add(match);
      }
    }

    // Sort by highest net profit boost first, then lowest detour distance
    matches.sort((a, b) {
      final profitComp = b.netProfitBoost.compareTo(a.netProfitBoost);
      if (profitComp != 0) return profitComp;
      return a.detourKm.compareTo(b.detourKm);
    });

    return matches;
  }
}
