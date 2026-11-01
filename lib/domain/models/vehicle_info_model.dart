class VehicleInfo {
  final String make;
  final String model;
  final int year;
  final String plate;
  final String color;
  final String type; // 'car', 'bike', 'rikshaw'

  const VehicleInfo({
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
    this.type = 'car',
  });

  Map<String, dynamic> toMap() => {
        'vehicleMake': make,
        'vehicleModel': model,
        'vehicleYear': year,
        'vehiclePlate': plate,
        'vehicleColor': color,
        'vehicleType': type,
      };

  factory VehicleInfo.fromMap(Map<String, dynamic> map) => VehicleInfo(
        make: map['vehicleMake'] ?? map['make'] ?? 'Toyota',
        model: map['vehicleModel'] ?? map['model'] ?? 'Camry',
        year: (map['vehicleYear'] ?? map['year'] as num?)?.toInt() ?? 2022,
        plate: map['vehiclePlate'] ?? map['plate'] ?? 'SWIFT-101',
        color: map['vehicleColor'] ?? map['color'] ?? 'Silver',
        type: map['vehicleType'] ?? map['type'] ?? 'car',
      );

  String get summary => '$color $make $model ($plate)';
}

extension VehicleInfoX on VehicleInfo {
  /// Resolves the car tier:
  /// 0 = Bike / Moto
  /// 1 = Auto Rikshaw
  /// 2 = Car Economy (Alto, Cultus, WagonR, Mira, Mehran)
  /// 3 = Car Sedan / Comfort AC (Corolla, Civic, Yaris, City)
  int get carTier {
    final t = type.toLowerCase().trim();
    if (t == 'bike' || t == 'motorcycle' || t == 'moto') return 0;
    if (t == 'rikshaw' || t == 'rickshaw' || t == 'auto') return 1;
    final m = model.toLowerCase();
    if (m.contains('corolla') ||
        m.contains('civic') ||
        m.contains('city') ||
        m.contains('yaris') ||
        m.contains('camry') ||
        m.contains('alsvin') ||
        m.contains('elantra') ||
        m.contains('sonata') ||
        m.contains('accord') ||
        m.contains('sedan')) {
      return 3;
    }
    return 2; // Economy hatchback default (Alto, Cultus, WagonR)
  }

  /// Baseline city fuel economy in km/L based on car model
  double get baselineFuelAverageKmPerL {
    if (carTier == 0) return 38.0;
    if (carTier == 1) return 22.0;
    if (carTier == 3) return 10.0;
    final m = model.toLowerCase();
    if (m.contains('alto') || m.contains('mira') || m.contains('mehran') || m.contains('660')) {
      return 15.5;
    }
    return 13.0; // 1000cc Cultus / WagonR / Vitz
  }
}
