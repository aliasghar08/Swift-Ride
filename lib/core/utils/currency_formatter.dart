class CurrencyFormatter {
  /// Formats a number to USD currency string: e.g. 5.5 -> $5.50
  static String format(double amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }

  /// Formats duration in minutes into a friendly string: e.g. 14 -> 14 min
  static String formatDuration(double minutes) {
    if (minutes < 60) {
      return '${minutes.toInt()} min';
    }
    final hours = (minutes / 60).floor();
    final rem = (minutes % 60).toInt();
    return '${hours}h ${rem}m';
  }

  /// Formats distance in km: e.g. 4.8 -> 4.8 km
  static String formatDistance(double km) {
    return '${km.toStringAsFixed(1)} km';
  }
}
