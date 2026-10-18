import 'package:flutter/widgets.dart';

/// Unicode directional isolates (UAX #9). Invisible; they keep a run's own
/// direction inside a paragraph of the other direction.
final leftToRightIsolate = String.fromCharCode(0x2066);
final firstStrongIsolate = String.fromCharCode(0x2068);
final popDirectionalIsolate = String.fromCharCode(0x2069);

/// Wraps [text] so it always reads left to right, even inside Urdu.
String isolateLtr(String text) =>
    '$leftToRightIsolate$text$popDirectionalIsolate';

/// Wraps [text] so its direction follows its own first strong character.
String isolateAuto(String text) =>
    '$firstStrongIsolate$text$popDirectionalIsolate';

/// [text] kept left to right when the ambient direction is RTL; unchanged in
/// an LTR (English) context, so English output stays byte-for-byte the same.
String ltrInContext(BuildContext context, String text) =>
    Directionality.maybeOf(context) == TextDirection.rtl
    ? isolateLtr(text)
    : text;

/// An already formatted amount (`Rs 1025.00`, `-Rs 50.00`). Formatting and
/// arithmetic stay in the existing helpers; this only fixes its direction.
String bidiMoney(BuildContext context, String formatted) =>
    ltrInContext(context, formatted);

/// An already formatted quantity (`2.5 kg`, `750 ml`, `3`).
String bidiQuantity(BuildContext context, String formatted) =>
    ltrInContext(context, formatted);

/// An identifier that must never reorder or be translated: barcode, bill
/// reference, phone, email, device or invoice number.
String bidiId(BuildContext context, String identifier) =>
    ltrInContext(context, identifier);

/// Shopkeeper-entered text (product, category, customer or cashier name,
/// address): kept exactly as entered, in its own direction, inside an Urdu
/// line, so an English name's trailing `)` or `.` never jumps to the wrong
/// side. Unchanged in an LTR (English) context.
String bidiName(BuildContext context, String name) =>
    Directionality.maybeOf(context) == TextDirection.rtl
    ? isolateAuto(name)
    : name;

/// The direction of [text]'s first strong character, or null when it has
/// none (digits, punctuation, empty). Used so shopkeeper-entered names keep
/// their own direction whatever the UI language.
TextDirection? textDirectionOf(String text) {
  for (final rune in text.runes) {
    if (_isRtl(rune)) return TextDirection.rtl;
    if (_isLtrLetter(rune)) return TextDirection.ltr;
  }
  return null;
}

bool _isRtl(int rune) =>
    (rune >= 0x0590 && rune <= 0x08FF) || // Hebrew, Arabic (incl. Urdu)
    (rune >= 0xFB1D && rune <= 0xFDFF) || // presentation forms A
    (rune >= 0xFE70 && rune <= 0xFEFF) || // presentation forms B
    (rune >= 0x10800 && rune <= 0x10FFF) ||
    (rune >= 0x1E800 && rune <= 0x1EFFF);

bool _isLtrLetter(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A) ||
    (rune >= 0xC0 && rune <= 0x24F && rune != 0xD7 && rune != 0xF7);
