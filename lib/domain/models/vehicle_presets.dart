import 'package:flutter/material.dart';

/// Exterior color swatch definition with name and display color.
class VehicleColorSwatch {
  final String name;
  final Color color;
  final String hex;

  const VehicleColorSwatch({
    required this.name,
    required this.color,
    required this.hex,
  });
}

/// Structured, Pakistan-localized vehicle presets dynamically filtered by vehicle type.
class VehiclePresets {
  const VehiclePresets._();

  /// Popular Pakistani car models (hatchbacks, sedans, crossovers).
  static const List<String> carModels = [
    'Toyota Corolla',
    'Suzuki Alto',
    'Suzuki Cultus',
    'Suzuki Wagon R',
    'Honda City',
    'Honda Civic',
    'Toyota Yaris',
    'Daihatsu Mira',
    'Suzuki Mehran',
    'Changan Alsvin',
    'KIA Picanto',
  ];

  /// Popular Pakistani motorbikes.
  static const List<String> bikeModels = [
    'Honda CD 70',
    'Honda CG 125',
    'Yamaha YBR 125',
    'Suzuki GS 150',
    'United US 70',
    'Road Prince 70',
    'Honda Pridor 100',
  ];

  /// Popular Pakistani auto rikshaws.
  static const List<String> rikshawModels = [
    'Sazgar 4-Stroke',
    'Qingqi Auto Rikshaw',
    'Rozgar Auto',
    'United Auto Rikshaw',
    'New Asia Auto',
  ];

  /// Popular Pakistani 7-seater MPVs and family vans.
  static const List<String> sevenSeaterModels = [
    'Changan Karvaan',
    'Suzuki Every',
    'Honda BR-V',
    'Suzuki Bolan',
    'Suzuki APV',
    'Toyota Sienta',
  ];

  /// Returns popular models based on vehicle type identifier.
  static List<String> modelsFor(String vehicleType) {
    final type = vehicleType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (type.contains('bike') || type.contains('moto')) {
      return bikeModels;
    }
    if (type.contains('rik') || type.contains('rick')) {
      return rikshawModels;
    }
    if (type.contains('seven') || type.contains('van') || type.contains('mpv') || type.contains('7seater')) {
      return sevenSeaterModels;
    }
    return carModels;
  }

  /// Regional number plate city/district prefixes across Pakistan.
  static const List<String> platePrefixes = [
    'JHG-',
    'LEA-',
    'FSD-',
    'LHR-',
    'RWP-',
    'ICT-',
    'KHI-',
    'MUX-',
  ];

  /// Model years for quick selection (descending from next year down to 2005).
  static List<int> get modelYears {
    final currentYear = DateTime.now().year;
    return List.generate((currentYear + 1) - 2005 + 1, (index) => (currentYear + 1) - index);
  }

  /// Curated exterior colors with exact hex color swatches.
  static const List<VehicleColorSwatch> colors = [
    VehicleColorSwatch(name: 'White', color: Color(0xFFFFFFFF), hex: '#FFFFFF'),
    VehicleColorSwatch(name: 'Silver', color: Color(0xFFC0C0C0), hex: '#C0C0C0'),
    VehicleColorSwatch(name: 'Black', color: Color(0xFF1A1A1A), hex: '#1A1A1A'),
    VehicleColorSwatch(name: 'Grey', color: Color(0xFF6B7280), hex: '#6B7280'),
    VehicleColorSwatch(name: 'Blue', color: Color(0xFF2563EB), hex: '#2563EB'),
    VehicleColorSwatch(name: 'Red', color: Color(0xFFDC2626), hex: '#DC2626'),
    VehicleColorSwatch(name: 'Pearl White', color: Color(0xFFF8FAFC), hex: '#F8FAFC'),
    VehicleColorSwatch(name: 'Green', color: Color(0xFF16A34A), hex: '#16A34A'),
    VehicleColorSwatch(name: 'Yellow', color: Color(0xFFEAB308), hex: '#EAB308'),
  ];

  /// Official Pakistani driving license authority prefixes.
  static const List<String> licensePrefixes = [
    'PK-DL-',
    'PB-',
    'ICT-',
    'SD-',
    'KP-',
  ];
}
