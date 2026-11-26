/// Comprehensive client & server validation utility for Pakistani vehicle registration,
/// license plates, model years, and driver credentials.
class VehicleValidator {
  const VehicleValidator._();

  static const Set<String> _gibberishPlaceholders = {
    'test',
    'asdf',
    '1234',
    '123',
    'car',
    'bike',
    'moto',
    'rikshaw',
    'rickshaw',
    'auto',
    'unknown',
    'n/a',
    'na',
    'none',
    'null',
    'xyz',
    'abc',
  };

  /// Normalizes vehicle plate to uppercase standard format `PREFIX-NUMBER` (e.g. `lea 2021` -> `LEA-2021`).
  static String normalizeLicensePlate(String? raw) {
    if (raw == null) return '';
    var clean = raw.trim().toUpperCase();
    if (clean.isEmpty) return '';

    // Replace whitespace, underscores, or slashes with hyphens
    clean = clean.replaceAll(RegExp(r'[\s_/]+'), '-');

    // If no hyphen present and format is e.g. LEA2021, split letters and digits
    if (!clean.contains('-')) {
      final match = RegExp(r'^([A-Z]{2,4})(\d{1,4}.*)$').firstMatch(clean);
      if (match != null) {
        clean = '${match.group(1)}-${match.group(2)}';
      }
    }

    // Collapse multiple consecutive hyphens
    clean = clean.replaceAll(RegExp(r'-+'), '-');
    return clean;
  }

  /// Normalizes driving license number to uppercase with clean characters.
  static String normalizeLicenseNumber(String? raw) {
    if (raw == null) return '';
    return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '-');
  }

  /// Validates vehicle make (e.g. `Toyota`, `Honda`, `Suzuki`).
  static String? validateMake(String? value) {
    final clean = (value ?? '').trim();
    if (clean.isEmpty) {
      return 'Vehicle make is required (e.g. Toyota, Suzuki).';
    }
    if (clean.length < 2 || clean.length > 50) {
      return 'Vehicle make must be between 2 and 50 characters.';
    }
    final letterCount = RegExp(r'[a-zA-Z]').allMatches(clean).length;
    if (letterCount < 2) {
      return 'Vehicle make must contain at least 2 letters.';
    }
    if (_gibberishPlaceholders.contains(clean.toLowerCase())) {
      return 'Please enter a genuine vehicle make (e.g. Toyota, Honda).';
    }
    return null;
  }

  /// Validates vehicle model (e.g. `Corolla`, `Alto`, `CD 70`).
  static String? validateModel(String? value) {
    final clean = (value ?? '').trim();
    if (clean.isEmpty) {
      return 'Vehicle model is required (e.g. Corolla, Alto).';
    }
    if (clean.length < 2 || clean.length > 50) {
      return 'Vehicle model must be between 2 and 50 characters.';
    }
    final letterCount = RegExp(r'[a-zA-Z]').allMatches(clean).length;
    if (letterCount < 2) {
      return 'Vehicle model must contain at least 2 letters.';
    }
    if (_gibberishPlaceholders.contains(clean.toLowerCase())) {
      return 'Please enter a genuine vehicle model (e.g. Corolla, Alto).';
    }
    return null;
  }

  /// Validates combined make and model.
  static String? validateMakeModel({String? make, String? model}) {
    final makeErr = validateMake(make);
    if (makeErr != null) return makeErr;
    return validateModel(model);
  }

  /// Validates Pakistani registration plate number (e.g. `JHG-412`, `LEA-2021`, `ICT-24-889`).
  static String? validateLicensePlate(String? value) {
    final normalized = normalizeLicensePlate(value);
    if (normalized.isEmpty) {
      return 'Registration plate number is required.';
    }

    // Must match standard Pakistani formats: 2-4 letters, hyphen, 1-4 digits, optional suffix
    final pakPlatePattern = RegExp(r'^[A-Z]{2,4}-[0-9]{1,4}(-[A-Z0-9]{1,4})?$');
    if (!pakPlatePattern.hasMatch(normalized)) {
      return 'Enter a valid Pakistani plate (e.g. LEA-2021 or JHG-412).';
    }

    // Reject known dummy / placeholder plates
    const dummyPlates = {
      'AAA-0000',
      'AAA-1111',
      'XXX-1234',
      'ABC-1234',
      'ABC-1111',
      'SWIFT-101',
      '000-0000',
      'TEST-123',
    };
    if (dummyPlates.contains(normalized)) {
      return 'Please enter your actual vehicle registration plate number.';
    }

    // Reject all-zero digits in number portion (e.g. LEA-0000, JHG-0)
    final parts = normalized.split('-');
    if (parts.length >= 2) {
      final numPart = parts[1];
      if (RegExp(r'^0+$').hasMatch(numPart)) {
        return 'Registration plate cannot have all zeros.';
      }
    }

    return null;
  }

  /// Validates model year between 1995 and (current year + 1).
  static String? validateModelYear(dynamic value) {
    int? year;
    if (value is int) {
      year = value;
    } else if (value is String) {
      year = int.tryParse(value.trim());
    }

    if (year == null) {
      return 'Please enter a valid 4-digit model year.';
    }

    final maxYear = DateTime.now().year + 1;
    if (year < 1995 || year > maxYear) {
      return 'Model year must be between 1995 and $maxYear.';
    }
    return null;
  }

  /// Validates exterior vehicle color.
  static String? validateColor(String? value) {
    final clean = (value ?? '').trim();
    if (clean.isEmpty) {
      return 'Vehicle color is required.';
    }
    if (clean.length < 3 || clean.length > 25) {
      return 'Vehicle color must be between 3 and 25 characters.';
    }
    // Only letters and spaces allowed
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(clean)) {
      return 'Vehicle color can only contain letters.';
    }
    if (_gibberishPlaceholders.contains(clean.toLowerCase())) {
      return 'Please enter a real vehicle color (e.g. White, Silver, Black).';
    }
    return null;
  }

  /// Validates Pakistani driving license number.
  static String? validateLicenseNumber(String? value) {
    final clean = normalizeLicenseNumber(value);
    if (clean.isEmpty) {
      return 'Driving license number is required.';
    }

    // Must be 6-20 alphanumeric characters, may include hyphens
    if (!RegExp(r'^[A-Z0-9-]{6,20}$').hasMatch(clean)) {
      return 'License # must be 6-20 letters/digits (e.g. PK-DL-12345).';
    }

    // Reject repeated or sequential dummy numbers
    const dummyLicenses = {
      '000000',
      '123456',
      '12345678',
      'AAAAAA',
      'TEST123',
      '111111',
      '999999',
    };
    final stripped = clean.replaceAll('-', '');
    if (dummyLicenses.contains(clean) || dummyLicenses.contains(stripped)) {
      return 'Please enter your genuine driving license number.';
    }

    return null;
  }

  /// Category constraint: returns enforced seats for vehicle type.
  static int getCategorySeats(String vehicleType) {
    final type = vehicleType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (type.contains('bike') || type.contains('moto')) {
      return 1;
    }
    if (type.contains('rik') || type.contains('rick')) {
      return 3;
    }
    if (type.contains('seven') || type.contains('van') || type.contains('mpv') || type.contains('7seater')) {
      return 6;
    }
    return 4;
  }

  /// Category constraint: returns whether AC is supported for vehicle type.
  static bool getCategoryAllowsAc(String vehicleType) {
    final type = vehicleType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (type.contains('bike') || type.contains('rik') || type.contains('rick')) {
      return false;
    }
    return true;
  }
}
