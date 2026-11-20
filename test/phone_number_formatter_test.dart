import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/core/utils/phone_number_formatter.dart';

void main() {
  group('PhoneNumberFormatter Tests', () {
    const formatter = PhoneNumberFormatter();

    test('PhoneNumberFormatter.clean strips leading zeros', () {
      expect(PhoneNumberFormatter.clean('03001234567'), '3001234567');
      expect(PhoneNumberFormatter.clean('003001234567'), '3001234567');
      expect(PhoneNumberFormatter.clean('0'), '');
      expect(PhoneNumberFormatter.clean('03'), '3');
    });

    test('PhoneNumberFormatter.clean strips pasted +92 or 92', () {
      expect(PhoneNumberFormatter.clean('+923001234567'), '3001234567');
      expect(PhoneNumberFormatter.clean('923001234567'), '3001234567');
      expect(PhoneNumberFormatter.clean('+9203001234567'), '3001234567');
    });

    test('PhoneNumberFormatter.clean limits to 10 national digits', () {
      // 11 digits without 0 should clamp to 10 digits
      expect(PhoneNumberFormatter.clean('300123456789'), '3001234567');
    });

    test('PhoneNumberFormatter.toE164 adds +92', () {
      expect(PhoneNumberFormatter.toE164('03001234567'), '+923001234567');
      expect(PhoneNumberFormatter.toE164('3001234567'), '+923001234567');
      expect(PhoneNumberFormatter.toE164('+923001234567'), '+923001234567');
    });

    test('formatEditUpdate formats text as user types or pastes', () {
      // Typing '0' produces empty
      var result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '0',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(result.text, '');
      expect(result.selection.baseOffset, 0);

      // Typing '03' strips 0 and leaves '3'
      result = formatter.formatEditUpdate(
        const TextEditingValue(text: '0', selection: TextSelection.collapsed(offset: 1)),
        const TextEditingValue(
          text: '03',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(result.text, '3');
      expect(result.selection.baseOffset, 1);

      // Pasting '03001234567' completes trailing number cleanly
      result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '03001234567',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      expect(result.text, '3001234567');
      expect(result.selection.baseOffset, 10);

      // Pasting '+92 300 1234567' with spaces and symbols
      result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '+92 300 1234567',
          selection: TextSelection.collapsed(offset: 15),
        ),
      );
      expect(result.text, '3001234567');
      expect(result.selection.baseOffset, 10);
    });
  });
}
