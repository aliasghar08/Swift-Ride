import 'dart:math';

/// Representation of a validated coordinate pair.
class ParsedCoordinates {
  final double latitude;
  final double longitude;

  const ParsedCoordinates({
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() => 'ParsedCoordinates(lat: $latitude, lng: $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedCoordinates &&
          runtimeType == other.runtimeType &&
          (latitude - other.latitude).abs() < 1e-6 &&
          (longitude - other.longitude).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(
        (latitude * 10000).round(),
        (longitude * 10000).round(),
      );
}

/// Client-side parser for coordinates pasted from Google Maps, WhatsApp,
/// or web browsers in various common formats.
class CoordinateParser {
  // 1 & 2. Standard and Signed Decimal:
  // e.g. "31.2634, 72.3517", "31.2634,72.3517", "31.2634, 72.3517, 15z", "-31.2634, 72.3517"
  static final RegExp _decimalCommaRegex = RegExp(
    r'''^[(\[]?\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)(?:\s*,\s*\d+(?:\.\d+)?z?)?\s*[)\]]?$''',
    caseSensitive: false,
  );

  // Space-separated decimal:
  // e.g. "31.2634 72.3517" (requires explicit decimals to avoid false-matching street/house numbers)
  static final RegExp _decimalSpaceRegex = RegExp(
    r'''^[(\[]?\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)(?:\s+\d+(?:\.\d+)?z?)?\s*[)\]]?$''',
    caseSensitive: false,
  );

  // 3. Google URL fragment:
  // e.g. "@31.2634,72.3517,15z" or "@31.2634,72.3517"
  static final RegExp _googleFragmentRegex = RegExp(
    r'''^@(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)(?:,\s*\d+(?:\.\d+)?z?)?$''',
    caseSensitive: false,
  );

  // 4. Full Google Maps URL:
  // query parameter (e.g. ?q=31.2634,72.3517 or &query=31.2634,72.3517 or ll=31.2634,72.3517)
  static final RegExp _urlQueryRegex = RegExp(
    r'''[?&](?:q|query|ll|center|daddr|destination)=(-?\d+(?:\.\d+)?)(?:%2C|,|\+|\s+)(-?\d+(?:\.\d+)?)''',
    caseSensitive: false,
  );

  // path fragment with @ (e.g. maps/@31.2634,72.3517,15z)
  static final RegExp _urlAtPathRegex = RegExp(
    r'''/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)''',
    caseSensitive: false,
  );

  // generic URL path coordinate pair (e.g. /place/31.2634,72.3517 or /search/31.2634,72.3517)
  static final RegExp _urlPathPairRegex = RegExp(
    r'''(?:place|search|dir)/(-?\d{1,2}(?:\.\d+)?)(?:%2C|,)(-?\d{1,3}(?:\.\d+)?)''',
    caseSensitive: false,
  );

  // 5. DMS (Degrees, Minutes, Seconds) format:
  // e.g. 31°15'48.2"N 72°21'06.1"E or 31°15'48.2"N, 72°21'06.1"E
  static final RegExp _dmsRegex = RegExp(
    r'''(\d{1,2})\s*[°ddeg]*\s*(\d{1,2})\s*['′mmin]*\s*(\d+(?:\.\d+)?)\s*["″''ssec]*\s*([NSns])'''
    r'''[\s,]+'''
    r'''(\d{1,3})\s*[°ddeg]*\s*(\d{1,2})\s*['′mmin]*\s*(\d+(?:\.\d+)?)\s*["″''ssec]*\s*([EWew])''',
  );

  // Degrees and decimal minutes format:
  // e.g. 31°15.803'N 72°21.102'E
  static final RegExp _ddmRegex = RegExp(
    r'''(\d{1,2})\s*[°ddeg]*\s*(\d+(?:\.\d+)?)\s*['′mmin]*\s*([NSns])'''
    r'''[\s,]+'''
    r'''(\d{1,3})\s*[°ddeg]*\s*(\d+(?:\.\d+)?)\s*['′mmin]*\s*([EWew])''',
  );

  /// Returns non-null when [input] contains a valid coordinate pair.
  /// Returns null when it looks like a normal text query or fails bounds checks.
  static ParsedCoordinates? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 1. Standard Decimal & 2. Signed Decimal (comma separated)
    final commaMatch = _decimalCommaRegex.firstMatch(trimmed);
    if (commaMatch != null) {
      final lat = double.tryParse(commaMatch.group(1)!);
      final lng = double.tryParse(commaMatch.group(2)!);
      final validated = _validate(lat, lng);
      if (validated != null) return validated;
    }

    // Space-separated decimal
    final spaceMatch = _decimalSpaceRegex.firstMatch(trimmed);
    if (spaceMatch != null) {
      final lat = double.tryParse(spaceMatch.group(1)!);
      final lng = double.tryParse(spaceMatch.group(2)!);
      final validated = _validate(lat, lng);
      if (validated != null) return validated;
    }

    // 3. Google URL fragment (@31.2634,72.3517,15z)
    final fragmentMatch = _googleFragmentRegex.firstMatch(trimmed);
    if (fragmentMatch != null) {
      final lat = double.tryParse(fragmentMatch.group(1)!);
      final lng = double.tryParse(fragmentMatch.group(2)!);
      final validated = _validate(lat, lng);
      if (validated != null) return validated;
    }

    // 4. Full Google Maps URL
    final isUrl = trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('maps.google.') ||
        trimmed.startsWith('www.google.') ||
        trimmed.startsWith('geo:');

    if (isUrl || trimmed.contains('google.com/maps') || trimmed.contains('maps.google')) {
      // Check query parameter (?q=... or &query=...)
      final queryMatch = _urlQueryRegex.firstMatch(trimmed);
      if (queryMatch != null) {
        final lat = double.tryParse(queryMatch.group(1)!);
        final lng = double.tryParse(queryMatch.group(2)!);
        final validated = _validate(lat, lng);
        if (validated != null) return validated;
      }

      // Check path /@lat,lng
      final atMatch = _urlAtPathRegex.firstMatch(trimmed);
      if (atMatch != null) {
        final lat = double.tryParse(atMatch.group(1)!);
        final lng = double.tryParse(atMatch.group(2)!);
        final validated = _validate(lat, lng);
        if (validated != null) return validated;
      }

      // Check /place/lat,lng or /search/lat,lng
      final pathPairMatch = _urlPathPairRegex.firstMatch(trimmed);
      if (pathPairMatch != null) {
        final lat = double.tryParse(pathPairMatch.group(1)!);
        final lng = double.tryParse(pathPairMatch.group(2)!);
        final validated = _validate(lat, lng);
        if (validated != null) return validated;
      }
    }

    // 5. DMS format
    final dmsMatch = _dmsRegex.firstMatch(trimmed);
    if (dmsMatch != null) {
      final latDeg = double.tryParse(dmsMatch.group(1)!);
      final latMin = double.tryParse(dmsMatch.group(2)!);
      final latSec = double.tryParse(dmsMatch.group(3)!);
      final latDir = dmsMatch.group(4)!.toUpperCase();

      final lngDeg = double.tryParse(dmsMatch.group(5)!);
      final lngMin = double.tryParse(dmsMatch.group(6)!);
      final lngSec = double.tryParse(dmsMatch.group(7)!);
      final lngDir = dmsMatch.group(8)!.toUpperCase();

      if (latDeg != null &&
          latMin != null &&
          latSec != null &&
          lngDeg != null &&
          lngMin != null &&
          lngSec != null) {
        double lat = latDeg + (latMin / 60.0) + (latSec / 3600.0);
        if (latDir == 'S') lat = -lat;

        double lng = lngDeg + (lngMin / 60.0) + (lngSec / 3600.0);
        if (lngDir == 'W') lng = -lng;

        final validated = _validate(lat, lng);
        if (validated != null) return validated;
      }
    }

    // Decimal minutes (DDM) format fallback
    final ddmMatch = _ddmRegex.firstMatch(trimmed);
    if (ddmMatch != null) {
      final latDeg = double.tryParse(ddmMatch.group(1)!);
      final latMin = double.tryParse(ddmMatch.group(2)!);
      final latDir = ddmMatch.group(3)!.toUpperCase();

      final lngDeg = double.tryParse(ddmMatch.group(4)!);
      final lngMin = double.tryParse(ddmMatch.group(5)!);
      final lngDir = ddmMatch.group(6)!.toUpperCase();

      if (latDeg != null &&
          latMin != null &&
          lngDeg != null &&
          lngMin != null) {
        double lat = latDeg + (latMin / 60.0);
        if (latDir == 'S') lat = -lat;

        double lng = lngDeg + (lngMin / 60.0);
        if (lngDir == 'W') lng = -lng;

        final validated = _validate(lat, lng);
        if (validated != null) return validated;
      }
    }

    return null;
  }

  static ParsedCoordinates? _validate(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    if (lat.isNaN || lng.isNaN) return null;
    if (lat < -90.0 || lat > 90.0) return null;
    if (lng < -180.0 || lng > 180.0) return null;
    return ParsedCoordinates(latitude: lat, longitude: lng);
  }
}
