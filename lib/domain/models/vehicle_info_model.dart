class VehicleInfo {
  final String make;
  final String model;
  final int year;
  final String plate;
  final String color;

  const VehicleInfo({
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
  });

  Map<String, dynamic> toMap() => {
        'vehicleMake': make,
        'vehicleModel': model,
        'vehicleYear': year,
        'vehiclePlate': plate,
        'vehicleColor': color,
      };

  factory VehicleInfo.fromMap(Map<String, dynamic> map) => VehicleInfo(
        make: map['vehicleMake'] ?? map['make'] ?? 'Toyota',
        model: map['vehicleModel'] ?? map['model'] ?? 'Camry',
        year: (map['vehicleYear'] ?? map['year'] as num?)?.toInt() ?? 2022,
        plate: map['vehiclePlate'] ?? map['plate'] ?? 'SWIFT-101',
        color: map['vehicleColor'] ?? map['color'] ?? 'Silver',
      );

  String get summary => '$color $make $model ($plate)';
}
