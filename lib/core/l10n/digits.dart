import 'package:flutter/services.dart';

/// Western digits everywhere (Stage 2, D3): Urdu and Arabic keyboards type
/// Extended Arabic-Indic (۰–۹) or Arabic-Indic (٠–٩) digits and the Arabic
/// decimal and thousands separators. They are mapped to ASCII before any
/// parser sees them; ASCII input is returned unchanged.
///
/// Every mapped character is one UTF-16 code unit and maps to one, so text
/// length and cursor offsets never move.
String normalizeDigits(String input) {
  StringBuffer? out;
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    final mapped = switch (unit) {
      >= 0x06F0 && <= 0x06F9 => 0x30 + unit - 0x06F0, // Urdu ۰–۹
      >= 0x0660 && <= 0x0669 => 0x30 + unit - 0x0660, // Arabic ٠–٩
      0x066B => 0x2E, // Arabic decimal separator ٫ -> .
      0x066C => 0x2C, // Arabic thousands separator ٬ -> ,
      _ => null,
    };
    if (mapped != null) {
      out ??= StringBuffer(input.substring(0, i));
      out.writeCharCode(mapped);
    } else {
      out?.writeCharCode(unit);
    }
  }
  return out?.toString() ?? input;
}

/// Shows and stores Western digits in numeric, phone, PIN and barcode fields.
/// Must run before any ASCII-only filter (e.g. `digitsOnly`), which would
/// otherwise silently drop Urdu digits.
final class AsciiDigitsFormatter extends TextInputFormatter {
  const AsciiDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = normalizeDigits(newValue.text);
    return identical(text, newValue.text)
        ? newValue
        : newValue.copyWith(text: text);
  }
}
