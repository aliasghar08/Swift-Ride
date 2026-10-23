import 'package:flutter/material.dart';

/// Supported ride vehicle categories in SwiftRide.
enum VehicleType {
  car,
  bike,
  rikshaw,
}

extension VehicleTypeX on VehicleType {
  /// Unique identifier matching database string
  String get id => name;

  /// User-facing display title
  String get title {
    switch (this) {
      case VehicleType.car:
        return 'Car / AC';
      case VehicleType.bike:
        return 'Bike / Moto';
      case VehicleType.rikshaw:
        return 'Auto Rikshaw';
    }
  }

  /// Short description
  String get subtitle {
    switch (this) {
      case VehicleType.car:
        return 'Comfortable & Air Conditioned • 4 Seats';
      case VehicleType.bike:
        return 'Fastest in traffic • Solo 1 Seat';
      case VehicleType.rikshaw:
        return 'Economical • 2 Seats';
    }
  }

  /// Passenger seating capacity (1 for bike, 2 for auto rikshaw, 4 for car)
  int get seats {
    switch (this) {
      case VehicleType.car:
        return 4;
      case VehicleType.bike:
        return 1;
      case VehicleType.rikshaw:
        return 2;
    }
  }

  /// Base vehicle fuel mileage in kilometers per liter
  double get averageMileageKmPerL {
    switch (this) {
      case VehicleType.car:
        return 10.0; // Baseline car mileage in PKR city conditions
      case VehicleType.rikshaw:
        return 22.0; // 4-stroke auto rickshaw
      case VehicleType.bike:
        return 30.0; // Motorcycle / 70cc-125cc real-world city average
    }
  }

  /// Predicts real-world fuel mileage (km/L) using Google Maps route data (distance, traffic duration, congestion).
  double predictMileage({
    required double distanceKm,
    double? durationMin,
    double? staticDurationMin,
    String? trafficLevel,
  }) {
    final base = averageMileageKmPerL;
    if (this != VehicleType.car || distanceKm <= 0) {
      return base;
    }

    // Effective trip duration in minutes
    final effectiveDuration = (durationMin != null && durationMin > 0)
        ? durationMin
        : (distanceKm * 2.0).clamp(5.0, 999.0);

    // Calculate real-world average speed (km/h) from Google Maps route
    final avgSpeedKmH = (distanceKm / (effectiveDuration / 60.0)).clamp(5.0, 120.0);

    // Traffic delay factor from Google Maps static vs traffic duration
    double trafficPenalty = 0.0;
    if (staticDurationMin != null && staticDurationMin > 0 && durationMin != null && durationMin > 0) {
      final delayRatio = durationMin / staticDurationMin;
      if (delayRatio > 1.35) {
        trafficPenalty = 1.8; // severe stop-and-go congestion
      } else if (delayRatio > 1.15) {
        trafficPenalty = 0.9; // moderate traffic delay
      }
    } else if (trafficLevel != null) {
      final level = trafficLevel.toUpperCase();
      if (level == 'HEAVY') {
        trafficPenalty = 1.8;
      } else if (level == 'MODERATE') {
        trafficPenalty = 0.8;
      }
    }

    // Speed curve adjustment for car (city vs highway)
    double speedAdjustment;
    if (avgSpeedKmH < 15.0) {
      // Heavy urban crawl
      speedAdjustment = -1.8;
    } else if (avgSpeedKmH < 25.0) {
      // Typical city stop-and-go
      speedAdjustment = -0.8;
    } else if (avgSpeedKmH <= 45.0) {
      // Normal urban flow
      speedAdjustment = 0.4;
    } else if (avgSpeedKmH <= 75.0) {
      // Cruising speed (ring road / bypass / arterial)
      speedAdjustment = 1.8;
    } else {
      // High highway speed
      speedAdjustment = 1.0;
    }

    final predicted = (base + speedAdjustment - trafficPenalty).clamp(6.5, 14.0);
    return (predicted * 10).round() / 10.0;
  }

  /// Wear & tear maintenance expense rate in PKR per km
  double get maintenanceRatePerKm {
    switch (this) {
      case VehicleType.car:
        return 4.0; // Engine oil, brakes, tires
      case VehicleType.rikshaw:
        return 2.5;
      case VehicleType.bike:
        return 1.5;
    }
  }

  /// Standard reference petrol price in PKR per liter
  static const double standardFuelPricePerL = 285.0;

  /// Price multiplier relative to baseline car fare
  double get fareMultiplier {
    switch (this) {
      case VehicleType.car:
        return 1.0;
      case VehicleType.rikshaw:
        return 0.70;
      case VehicleType.bike:
        return 0.45;
    }
  }

  /// Minimum fare floor in PKR
  double get minFare {
    switch (this) {
      case VehicleType.car:
        return 80.0;
      case VehicleType.rikshaw:
        return 50.0;
      case VehicleType.bike:
        return 40.0;
    }
  }

  /// Typical pickup ETA in minutes
  int get typicalEtaMinutes {
    switch (this) {
      case VehicleType.bike:
        return 3;
      case VehicleType.rikshaw:
        return 4;
      case VehicleType.car:
        return 6;
    }
  }

  /// Material icon for vehicle category
  IconData get icon {
    switch (this) {
      case VehicleType.car:
        return Icons.directions_car_filled_rounded;
      case VehicleType.bike:
        return Icons.two_wheeler_rounded;
      case VehicleType.rikshaw:
        return Icons.electric_rickshaw_rounded;
    }
  }

  /// Calculates calibrated fare rounded to PKR 5 and constrained by floor
  double calculateFare(double baseCarFare) {
    final raw = baseCarFare * fareMultiplier;
    final rounded = (raw / 5.0).round() * 5.0;
    return rounded < minFare ? minFare : rounded;
  }

  /// Parses string to VehicleType with fallback to car
  static VehicleType fromString(String? val) {
    if (val == null) return VehicleType.car;
    final lower = val.toLowerCase().trim();
    if (lower == 'bike' || lower == 'motorcycle' || lower == 'moto') {
      return VehicleType.bike;
    }
    if (lower == 'rikshaw' || lower == 'rickshaw' || lower == 'auto' || lower == 'qingqi') {
      return VehicleType.rikshaw;
    }
    return VehicleType.car;
  }
}
