import 'vehicle_type.dart';
import '../../services/fuel_price_service.dart';

/// Comprehensive financial and fuel economics for a trip in SwiftRide.
/// Calculates fuel cost based on live fuel prices fetched from the internet & vehicle mileage,
/// vehicle wear & tear maintenance, platform service charges, and net driver take-home profit.
class TripEconomics {
  final double distanceKm;
  final double durationMin;
  final double totalFare;
  final double fuelPricePerL;
  final String fuelPriceSource;
  final bool isFuelPriceLive;
  final double vehicleMileageKmPerL;
  final double fuelConsumedLiters;
  final double fuelCost;
  final double maintenanceRatePerKm;
  final double maintenanceCost;
  final double serviceCharges; // 0% Commission
  final double driverTotalExpenses;
  final double driverNetProfit;
  final double profitPerMinute;
  final int bookedSeats;
  final int totalSeats;
  final VehicleType vehicleType;
  final bool isPredictedFromGoogleMaps;
  final String? trafficConditionNote;
  final bool isAiPredicted;

  const TripEconomics({
    required this.distanceKm,
    required this.durationMin,
    required this.totalFare,
    required this.fuelPricePerL,
    required this.fuelPriceSource,
    required this.isFuelPriceLive,
    required this.vehicleMileageKmPerL,
    required this.fuelConsumedLiters,
    required this.fuelCost,
    required this.maintenanceRatePerKm,
    required this.maintenanceCost,
    required this.serviceCharges,
    required this.driverTotalExpenses,
    required this.driverNetProfit,
    required this.profitPerMinute,
    required this.bookedSeats,
    required this.totalSeats,
    required this.vehicleType,
    this.isPredictedFromGoogleMaps = false,
    this.trafficConditionNote,
    this.isAiPredicted = false,
  });

  double get fuelCostPkr => fuelCost;
  double get maintenanceCostPkr => maintenanceCost;

  /// Factory calculator evaluating fuel, maintenance, and driver profit in real-time.
  /// Automatically uses live internet fuel rates from [FuelPriceService] when not overridden.
  factory TripEconomics.calculate({
    required double distanceKm,
    double durationMin = 0.0,
    double? staticDurationMin,
    String? trafficLevel,
    required double fare,
    required VehicleType vehicleType,
    int bookedSeats = 1,
    double? fuelPricePerL,
    String? fuelPriceSource,
    bool? isFuelPriceLive,
    bool isAiPredicted = false,
  }) {
    final effectiveDuration = durationMin > 0
        ? durationMin
        : (distanceKm > 0 ? (distanceKm * 2.0).clamp(5.0, 999.0) : 5.0);

    // Retrieve live fuel price from FuelPriceService if not explicitly specified
    final livePrice = FuelPriceService().currentPrice;
    final effectiveFuelPrice = fuelPricePerL ?? livePrice.petrolPricePerL;
    final effectiveSource = fuelPriceSource ?? livePrice.source;
    final effectiveIsLive = isFuelPriceLive ?? livePrice.isLive;

    // Predict car mileage dynamically from Google Maps route data (distance, speed, traffic)
    final mileage = vehicleType == VehicleType.car
        ? vehicleType.predictMileage(
            distanceKm: distanceKm,
            durationMin: effectiveDuration,
            staticDurationMin: staticDurationMin,
            trafficLevel: trafficLevel,
          )
        : vehicleType.averageMileageKmPerL;

    final isPredicted = vehicleType == VehicleType.car;
    String? trafficNote;
    if (isPredicted) {
      if (mileage < 9.0) {
        trafficNote = 'Heavy traffic (~${mileage.toStringAsFixed(1)} km/L via Google Maps)';
      } else if (mileage > 11.0) {
        trafficNote = 'Highway/free flow (~${mileage.toStringAsFixed(1)} km/L via Google Maps)';
      } else {
        trafficNote = 'Normal traffic (~${mileage.toStringAsFixed(1)} km/L via Google Maps)';
      }
    }

    final maintRate = vehicleType.maintenanceRatePerKm;
    final liters = distanceKm > 0 && mileage > 0 ? (distanceKm / mileage) : 0.0;
    final fuel = (liters * effectiveFuelPrice * 10).round() / 10.0;
    final maint = (distanceKm * maintRate * 10).round() / 10.0;
    const serviceFee = 0.0; // SwiftRide 0% Commission Guarantee
    final expenses = ((fuel + maint + serviceFee) * 10).round() / 10.0;
    final profit = (fare - expenses).clamp(0.0, 999999.0);
    final profitRate = effectiveDuration > 0
        ? (profit / effectiveDuration * 10).round() / 10.0
        : 0.0;

    return TripEconomics(
      distanceKm: distanceKm,
      durationMin: effectiveDuration,
      totalFare: fare,
      fuelPricePerL: effectiveFuelPrice,
      fuelPriceSource: effectiveSource,
      isFuelPriceLive: effectiveIsLive,
      vehicleMileageKmPerL: mileage,
      fuelConsumedLiters: (liters * 100).round() / 100.0,
      fuelCost: fuel,
      maintenanceRatePerKm: maintRate,
      maintenanceCost: maint,
      serviceCharges: serviceFee,
      driverTotalExpenses: expenses,
      driverNetProfit: (profit * 10).round() / 10.0,
      profitPerMinute: profitRate,
      bookedSeats: bookedSeats.clamp(1, vehicleType.seats),
      totalSeats: vehicleType.seats,
      vehicleType: vehicleType,
      isPredictedFromGoogleMaps: isPredicted,
      trafficConditionNote: trafficNote,
      isAiPredicted: isAiPredicted,
    );
  }

  Map<String, dynamic> toMap() => {
        'distanceKm': distanceKm,
        'durationMin': durationMin,
        'totalFare': totalFare,
        'fuelPricePerL': fuelPricePerL,
        'fuelPriceSource': fuelPriceSource,
        'isFuelPriceLive': isFuelPriceLive,
        'vehicleMileageKmPerL': vehicleMileageKmPerL,
        'fuelConsumedLiters': fuelConsumedLiters,
        'fuelCost': fuelCost,
        'maintenanceRatePerKm': maintenanceRatePerKm,
        'maintenanceCost': maintenanceCost,
        'serviceCharges': serviceCharges,
        'driverTotalExpenses': driverTotalExpenses,
        'driverNetProfit': driverNetProfit,
        'profitPerMinute': profitPerMinute,
        'bookedSeats': bookedSeats,
        'totalSeats': totalSeats,
        'vehicleType': vehicleType.id,
        'isPredictedFromGoogleMaps': isPredictedFromGoogleMaps,
        'trafficConditionNote': trafficConditionNote,
        'isAiPredicted': isAiPredicted,
      };
}
