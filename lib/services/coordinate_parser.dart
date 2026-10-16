import 'dart:math';

/// Representation of a validated coordinate pair or resolved pinned location.
class ParsedCoordinates {
  final double latitude;
  final double longitude;
  final String? label;
  final String? originalCode;

  const ParsedCoordinates({
    required this.latitude,
    required this.longitude,
    this.label,
    this.originalCode,
  });

  @override
  String toString() =>
      'ParsedCoordinates(lat: $latitude, lng: $longitude, label: $label, code: $originalCode)';

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

/// Client-side parser for coordinates and pinned locations (including Google Maps
/// Plus Codes / Open Location Codes e.g. "78G5+48 Jhang, Pakistan", DMS, URLs,
/// and raw decimal pairs).
class CoordinateParser {
  // Major Pakistani cities with center coordinates for locality reference
  static const Map<String, ({double lat, double lng})> pakistanCities = {
    'jhang': (lat: 31.2681, lng: 72.3181),
    'toba tek singh': (lat: 30.9747, lng: 72.4828),
    'sargodha': (lat: 32.0836, lng: 72.6711),
    'faisalabad': (lat: 31.4504, lng: 73.1350),
    'lahore': (lat: 31.5497, lng: 74.3436),
    'islamabad': (lat: 33.6844, lng: 73.0479),
    'rawalpindi': (lat: 33.5651, lng: 73.0169),
    'karachi': (lat: 24.8607, lng: 67.0011),
    'multan': (lat: 30.1575, lng: 71.5249),
    'peshawar': (lat: 34.0151, lng: 71.5249),
    'quetta': (lat: 30.1798, lng: 66.9750),
    'gujranwala': (lat: 32.1877, lng: 74.1945),
    'sialkot': (lat: 32.4945, lng: 74.5229),
    'bahawalpur': (lat: 29.3544, lng: 71.6911),
    'sukkur': (lat: 27.7052, lng: 68.8574),
    'hyderabad': (lat: 25.3960, lng: 68.3578),
    'chiniot': (lat: 31.7200, lng: 72.9789),
    'bhakkar': (lat: 31.6253, lng: 71.0657),
    'mianwali': (lat: 32.5839, lng: 71.5370),
    'khushab': (lat: 32.2955, lng: 72.3503),
    'sahiwal': (lat: 30.6682, lng: 73.1114),
    'okara': (lat: 30.8080, lng: 73.4458),
    'sheikhupura': (lat: 31.7131, lng: 73.9783),
    'kasur': (lat: 31.1179, lng: 74.4461),
    'jhelum': (lat: 32.9405, lng: 73.7276),
    'attock': (lat: 33.7660, lng: 72.3609),
    'chakwal': (lat: 32.9328, lng: 72.8630),
    'abbottabad': (lat: 34.1688, lng: 73.2215),
    'murree': (lat: 33.9070, lng: 73.3943),
    'gilgit': (lat: 35.9221, lng: 74.3087),
    'skardu': (lat: 35.2971, lng: 75.6333),
  };

  // Open Location Code (Plus Code) standard alphabet
  static const String _olcAlphabet = '23456789CFGHJMPQRVWX';

  // Plus Code regex: matches 4 to 8 characters + '+' + 2 to 4 characters
  // e.g. "78G5+48", "8J3J78G5+48", "78HJ+CM"
  static final RegExp _plusCodeRegex = RegExp(
    r'''\b([23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,4})\b''',
    caseSensitive: false,
  );

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

  /// Returns non-null when [input] contains a valid coordinate pair or Plus Code.
  /// Accepts optional [referenceLat] and [referenceLng] for resolving short Plus Codes.
  static ParsedCoordinates? tryParse(
    String input, {
    double? referenceLat,
    double? referenceLng,
  }) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Handle "Dropped pin" or "Pinned location" prefixes copied from Google Maps
    // e.g. "Dropped pin near 78G5+48 Jhang, Pakistan" or "Pinned location:\n31.2634, 72.3517"
    final droppedPinPrefix = RegExp(
      r'''^(?:dropped\s+pin|pinned\s+location|pinned\s+spot|location)[\s:\n]*(?:near\s+)?''',
      caseSensitive: false,
    );
    final cleanInput = trimmed.replaceFirst(droppedPinPrefix, '').trim();
    final target = cleanInput.isNotEmpty ? cleanInput : trimmed;

    // 1. Check for Plus Codes / Open Location Codes (e.g. "78G5+48 Jhang, Pakistan", "8J3J78G5+48")
    final plusMatch = _plusCodeRegex.firstMatch(target);
    if (plusMatch != null) {
      final code = plusMatch.group(1)!.toUpperCase();
      final locality = target.replaceAll(plusMatch.group(0)!, '').trim();
      final parsed = _resolvePlusCode(
        code,
        locality: locality,
        referenceLat: referenceLat,
        referenceLng: referenceLng,
      );
      if (parsed != null) return parsed;
    }

    // 2. Standard Decimal & Signed Decimal (comma separated)
    final commaMatch = _decimalCommaRegex.firstMatch(target);
    if (commaMatch != null) {
      final lat = double.tryParse(commaMatch.group(1)!);
      final lng = double.tryParse(commaMatch.group(2)!);
      final validated = _validate(lat, lng, label: 'Coordinates ($lat, $lng)');
      if (validated != null) return validated;
    }

    // Space-separated decimal
    final spaceMatch = _decimalSpaceRegex.firstMatch(target);
    if (spaceMatch != null) {
      final lat = double.tryParse(spaceMatch.group(1)!);
      final lng = double.tryParse(spaceMatch.group(2)!);
      final validated = _validate(lat, lng, label: 'Coordinates ($lat, $lng)');
      if (validated != null) return validated;
    }

    // 3. Google URL fragment (@31.2634,72.3517,15z)
    final fragmentMatch = _googleFragmentRegex.firstMatch(target);
    if (fragmentMatch != null) {
      final lat = double.tryParse(fragmentMatch.group(1)!);
      final lng = double.tryParse(fragmentMatch.group(2)!);
      final validated = _validate(lat, lng, label: 'Pinned Coordinates');
      if (validated != null) return validated;
    }

    // 4. Full Google Maps URL
    final isUrl = target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('maps.google.') ||
        target.startsWith('www.google.') ||
        target.startsWith('geo:');

    if (isUrl || target.contains('google.com/maps') || target.contains('maps.google')) {
      // Decode any URL encoding (e.g. %2B -> +, %2C -> ,)
      String decodedUrl = target;
      try {
        decodedUrl = Uri.decodeFull(target);
      } catch (_) {}

      // Check if URL contains a plus code in query
      final urlPlusMatch = _plusCodeRegex.firstMatch(decodedUrl);
      if (urlPlusMatch != null) {
        final code = urlPlusMatch.group(1)!.toUpperCase();
        final parsed = _resolvePlusCode(
          code,
          locality: decodedUrl,
          referenceLat: referenceLat,
          referenceLng: referenceLng,
        );
        if (parsed != null) return parsed;
      }

      // Check query parameter (?q=... or &query=...)
      final queryMatch = _urlQueryRegex.firstMatch(decodedUrl);
      if (queryMatch != null) {
        final lat = double.tryParse(queryMatch.group(1)!);
        final lng = double.tryParse(queryMatch.group(2)!);
        final validated = _validate(lat, lng, label: 'Shared Map Pin');
        if (validated != null) return validated;
      }

      // Check path /@lat,lng
      final atMatch = _urlAtPathRegex.firstMatch(decodedUrl);
      if (atMatch != null) {
        final lat = double.tryParse(atMatch.group(1)!);
        final lng = double.tryParse(atMatch.group(2)!);
        final validated = _validate(lat, lng, label: 'Shared Map Pin');
        if (validated != null) return validated;
      }

      // Check /place/lat,lng or /search/lat,lng
      final pathPairMatch = _urlPathPairRegex.firstMatch(decodedUrl);
      if (pathPairMatch != null) {
        final lat = double.tryParse(pathPairMatch.group(1)!);
        final lng = double.tryParse(pathPairMatch.group(2)!);
        final validated = _validate(lat, lng, label: 'Shared Map Pin');
        if (validated != null) return validated;
      }
    }

    // 5. DMS format
    final dmsMatch = _dmsRegex.firstMatch(target);
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

        final validated = _validate(lat, lng, label: 'DMS Coordinates');
        if (validated != null) return validated;
      }
    }

    // Decimal minutes (DDM) format fallback
    final ddmMatch = _ddmRegex.firstMatch(target);
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

        final validated = _validate(lat, lng, label: 'DDM Coordinates');
        if (validated != null) return validated;
      }
    }

    return null;
  }

  /// Resolves an Open Location Code / Plus Code to geographical coordinates.
  static ParsedCoordinates? _resolvePlusCode(
    String code, {
    String? locality,
    double? referenceLat,
    double? referenceLng,
  }) {
    final cleanCode = code.replaceAll(' ', '').toUpperCase();
    final plusIdx = cleanCode.indexOf('+');
    if (plusIdx < 0) return null;

    // Determine reference coordinates for short codes
    double refLat = referenceLat ?? 31.2681; // Default Jhang center
    double refLng = referenceLng ?? 72.3181;
    String detectedCity = 'Jhang';

    final loc = locality?.toLowerCase() ?? '';
    for (final entry in pakistanCities.entries) {
      final pattern = RegExp('\\b${entry.key}\\b', caseSensitive: false);
      if (pattern.hasMatch(loc)) {
        refLat = entry.value.lat;
        refLng = entry.value.lng;
        detectedCity = entry.key[0].toUpperCase() + entry.key.substring(1);
        break;
      }
    }

    try {
      final coords = _recoverNearestAndDecode(cleanCode, refLat, refLng);
      final displayLocality = (locality != null && locality.trim().isNotEmpty)
          ? locality.trim()
          : '$detectedCity, Pakistan';
      final cleanLocality = displayLocality.replaceAll(RegExp(r'^[,\s]+'), '');

      return _validate(
        coords.lat,
        coords.lng,
        label: cleanLocality.isNotEmpty
            ? '$cleanCode, $cleanLocality'
            : '$cleanCode, $detectedCity, Pakistan',
        originalCode: cleanCode,
      );
    } catch (_) {
      return null;
    }
  }

  /// Recovers a full 10-digit Open Location Code and decodes its center coordinates.
  static ({double lat, double lng, String fullCode}) _recoverNearestAndDecode(
    String code,
    double refLat,
    double refLng,
  ) {
    final plusIdx = code.indexOf('+');
    String fullCode = code;

    // If prefix is missing (short code e.g. "78G5+48"), recover from reference location
    if (plusIdx < 8) {
      final missingDigits = 8 - plusIdx;
      double latVal = refLat + 90.0;
      double lngVal = refLng + 180.0;
      final prefixBuf = StringBuffer();

      double latRes = 20.0;
      double lngRes = 20.0;
      final numPairs = missingDigits ~/ 2;

      for (int i = 0; i < numPairs; i++) {
        final latIdx = (latVal / latRes).floor().clamp(0, 19);
        final lngIdx = (lngVal / lngRes).floor().clamp(0, 19);
        prefixBuf.write(_olcAlphabet[latIdx]);
        prefixBuf.write(_olcAlphabet[lngIdx]);
        latVal -= latIdx * latRes;
        lngVal -= lngIdx * lngRes;
        latRes /= 20.0;
        lngRes /= 20.0;
      }

      fullCode = prefixBuf.toString() + code;
    }

    // Decode full 10-char code
    final clean = fullCode.replaceAll('+', '').toUpperCase();
    double lat = -90.0;
    double lng = -180.0;
    double latVal = 20.0;
    double lngVal = 20.0;

    final len = min(clean.length, 10);
    for (int i = 0; i < len; i += 2) {
      final latIndex = _olcAlphabet.indexOf(clean[i]);
      final lngIndex = _olcAlphabet.indexOf(clean[i + 1]);
      if (latIndex < 0 || lngIndex < 0) break;
      lat += latIndex * latVal;
      lng += lngIndex * lngVal;
      latVal /= 20.0;
      lngVal /= 20.0;
    }

    double centerLat = lat + (latVal * 20.0) / 2.0;
    double centerLng = lng + (lngVal * 20.0) / 2.0;

    // Optional 11th character: 4x5 subgrid refinement (e.g. 7972+7PF)
    if (clean.length > 10) {
      final gridIdx = _olcAlphabet.indexOf(clean[10]);
      if (gridIdx >= 0) {
        final row = gridIdx ~/ 4; // 5 rows (0..4)
        final col = gridIdx % 4; // 4 columns (0..3)
        centerLat = lat + row * (latVal / 5.0) + (latVal / 10.0);
        centerLng = lng + col * (lngVal / 4.0) + (lngVal / 8.0);
      }
    }

    // Normalize short code nearest recovery around reference coordinates
    if (plusIdx < 8) {
      final latDiff = centerLat - refLat;
      final lngDiff = centerLng - refLng;
      if (latDiff > 0.5) centerLat -= 1.0;
      if (latDiff < -0.5) centerLat += 1.0;
      if (lngDiff > 0.5) centerLng -= 1.0;
      if (lngDiff < -0.5) centerLng += 1.0;
    }

    return (lat: centerLat, lng: centerLng, fullCode: fullCode);
  }

  static ParsedCoordinates? _validate(
    double? lat,
    double? lng, {
    String? label,
    String? originalCode,
  }) {
    if (lat == null || lng == null) return null;
    if (lat.isNaN || lng.isNaN) return null;
    if (lat < -90.0 || lat > 90.0) return null;
    if (lng < -180.0 || lng > 180.0) return null;
    return ParsedCoordinates(
      latitude: lat,
      longitude: lng,
      label: label,
      originalCode: originalCode,
    );
  }
}
