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
