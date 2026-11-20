import 'package:flutter/services.dart';

/// Formatter for Pakistani mobile phone numbers entered into the app.
///
/// Features:
/// - Automatically removes leading zero(s) (e.g. `0300...` -> `300...`).
/// - Strips pasted international prefix `+92` or `92` so the clean 10-digit
///   national subscriber number remains.
/// - Ensures trailing numbers are never truncated by restricting length to
///   exactly 10 digits without an unnecessary leading zero occupying slot 0.
/// - Keeps the cursor accurately placed at the end of valid digits.
class PhoneNumberFormatter extends TextInputFormatter {
  const PhoneNumberFormatter();

  /// Cleans any raw phone string by stripping non-digits, country code 92,
  /// and any leading zeros, returning up to 10 national digits.
  static String clean(String raw) {
    if (raw.isEmpty) return '';
    var digits = raw.replaceAll(RegExp(r'\D'), '');

    // Strip pasted +92 or 92
    if (digits.startsWith('92') && digits.length > 2) {
      digits = digits.substring(2);
    }

    // Strip leading zeros
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    // Max 10 national digits (e.g. 3001234567)
    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }

    return digits;
  }

  /// Normalizes to standard E.164 (e.g. `+923001234567`).
  static String toE164(String raw, {String countryCode = '+92'}) {
    final cleaned = clean(raw);
    if (cleaned.isEmpty) return '';
    return '$countryCode$cleaned';
  }

  /// Formats for visual display with clean operator spacing: `300 1234567`.
  static String formatDisplay(String raw) {
    final cleaned = clean(raw);
    if (cleaned.length > 3) {
      return '${cleaned.substring(0, 3)} ${cleaned.substring(3)}';
    }
    return cleaned;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.isEmpty) {
      return newValue;
    }

    final cleaned = clean(newText);

    // Calculate cursor position
    int newOffset = cleaned.length;
    if (newValue.selection.end < newText.length) {
      // User was editing in the middle
      final leadingZerosRemoved = newText.length - newText.replaceFirst(RegExp(r'^0+'), '').length;
      newOffset = (newValue.selection.end - leadingZerosRemoved).clamp(0, cleaned.length);
    }

    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
