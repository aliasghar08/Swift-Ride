import 'dart:math';
import '../constants/app_constants.dart';

class DistanceCalculator {
  static const double earthRadiusKm = 6371.0;

  /// Computes direct distance between two coordinates in kilometers using Haversine formula.
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Computes estimated urban driving distance (approx 1.3x straight line distance).
  static double estimatedDrivingDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final straightKm = haversineDistance(lat1, lon1, lat2, lon2);
    final drivingKm = max(0.5, straightKm * 1.3);
    return (drivingKm * 10).round() / 10.0;
  }

  /// Computes estimated driving duration in minutes.
  static double estimatedDurationMinutes(double distanceKm) {
    // Average urban driving speed ~25-30 km/h -> ~2.2 minutes per km + 2 min buffer
    final min = max(3.0, (distanceKm * 2.2) + 2.0);
    return (min).roundToDouble();
  }

  /// Computes suggested fare based on SwiftRide formula, rounded to nearest 0.50.
  static double calculateSuggestedFare(double distanceKm, double durationMin) {
    final rawFare = AppConstants.baseFare +
        (distanceKm * AppConstants.perKmFare) +
        (durationMin * AppConstants.perMinFare);
    return (rawFare * 2).round() / 2.0;
  }

  /// Computes money saved by driver due to SwiftRide 0% commission vs 13% incumbent commission.
  static double calculateZeroCommissionSavings(double totalFares) {
    final savings = totalFares * AppConstants.standardIndustryCommission;
    return (savings * 100).round() / 100.0;
  }
}
