class CurrencyFormatter {
  /// Formats a number to PKR currency string: e.g. 450 -> PKR 450
  static String format(double amount) {
    if (amount % 1 == 0) {
      return 'PKR ${amount.toInt()}';
    }
    return 'PKR ${amount.toStringAsFixed(0)}';
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
