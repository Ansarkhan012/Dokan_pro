import 'dart:convert';

import '../domain/enums.dart';
import 'display_format.dart';

/// A measured quantity (thousandths of [unit]) for display, in integers only:
/// `250` → `250 g`, `1000` → `1 kg`, `1250` → `1.25 kg`; `750` of a liter
/// product → `750 ml`, `1500` → `1.5 L`. Below one whole unit the fraction
/// unit is used; from one whole unit up the whole unit with up to three
/// decimals.
String formatMeasureQuantity(int thousandths, MeasureUnit unit) {
  final sign = thousandths < 0 ? '-' : '';
  final absolute = thousandths.abs();
  if (absolute < 1000) return '$sign$absolute ${unit.fractionLabel}';
  return '$sign${formatDisplayQuantity(absolute)} ${unit.wholeLabel}';
}

/// A sale-line quantity: a measured line ([unit] set, from
/// `measure_unit_snapshot`) as a measure, otherwise as a count (`2`, `1.5`).
String formatLineQuantity(int thousandths, MeasureUnit? unit) => unit == null
    ? formatDisplayQuantity(thousandths)
    : formatMeasureQuantity(thousandths, unit);

/// The name a sellable product is sold and snapshotted under. A pack variant
/// (a product in a family) carries its pack label: `Tapal Danedar 250 g`.
/// Products outside a family keep their name exactly as before.
String sellableName(String name, String? packLabel, {String? familyId}) {
  final label = packLabel?.trim() ?? '';
  return familyId == null || label.isEmpty ? name : '$name $label';
}

/// Largest measured quantity a line, preset or stock entry may hold (U2):
/// 1,000 kg or 1,000 L in thousandths. Matches the server's preset bound.
const int maxMeasureQuantity = 1000000;

/// Quick quantities offered when the owner has not configured any.
const List<int> defaultMeasurePresets = [250, 500, 1000, 2000, 5000];

/// At most this many quick quantities per product (server-enforced too).
const int maxMeasurePresets = 8;

/// Parses a typed measured quantity into thousandths without floating point.
/// [fractionUnit] true reads whole grams / millilitres (`750` → 750); false
/// reads kilograms / litres with at most three decimals (`1.25` → 1250).
/// Returns null for anything else (signs, letters, excess precision).
int? parseMeasureInput(String input, {required bool fractionUnit}) {
  final text = input.trim();
  if (fractionUnit) {
    if (!RegExp(r'^\d{1,9}$').hasMatch(text)) return null;
    return int.parse(text);
  }
  final match = RegExp(r'^(\d{1,7})(?:\.(\d{1,3}))?$').firstMatch(text);
  if (match == null) return null;
  final fraction = (match.group(2) ?? '').padRight(3, '0');
  return int.parse(match.group(1)!) * 1000 + int.parse(fraction);
}

/// Why [thousandths] cannot be sold or configured, or null when it can.
String? measureQuantityError(int? thousandths) {
  if (thousandths == null) return 'Enter a valid quantity.';
  if (thousandths <= 0) return 'Quantity must be more than zero.';
  if (thousandths > maxMeasureQuantity) return 'Quantity is too large.';
  return null;
}

/// Owner-configured quick quantities as stored locally (a JSON array of
/// thousandths), or null when unset or unreadable.
List<int>? decodeMeasurePresets(String? stored) {
  if (stored == null || stored.isEmpty) return null;
  try {
    final values = (jsonDecode(stored) as List).map((v) => (v as num).toInt()).toList();
    return values.isEmpty ? null : values;
  } catch (_) {
    return null;
  }
}

/// `Rs 130.00/kg` style unit price label.
String measureUnitPriceLabel(String formattedPrice, MeasureUnit unit) =>
    '$formattedPrice/${unit.wholeLabel}';
