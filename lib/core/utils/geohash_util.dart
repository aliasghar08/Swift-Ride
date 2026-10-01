class GeohashUtil {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encodes latitude and longitude into a geohash string of given precision.
  static String encode(double latitude, double longitude, [int precision = 7]) {
    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;

    final StringBuffer geohash = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;

    while (geohash.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch |= (1 << (4 - bit));
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        geohash.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return geohash.toString();
  }

  /// Calculates coarse prefix for Firestore range queries.
  static String coarsePrefix(double latitude, double longitude) {
    return encode(latitude, longitude, 5);
  }
}
