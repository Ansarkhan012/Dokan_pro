import '../../l10n/app_localizations.dart';
import '../domain/enums.dart';
import '../format/display_format.dart';

/// Locale-aware versions of `display_format.dart` and `measure_format.dart`
/// for widgets. With English they return exactly what the original helpers
/// return; digits are always Western (Stage 2, D3). Presentation only: never
/// parse these back or store them.

/// `5 Oct 2026` / `5 اکتوبر 2026`, in device-local time.
String localizedDate(AppLocalizations l10n, DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${l10n.monthShort('${local.month}')} ${local.year}';
}

/// `1:17 PM`, in device-local time.
String localizedTime(AppLocalizations l10n, DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? l10n.timeAm : l10n.timePm}';
}

/// `5 Oct 2026 • 1:17 PM` (or with a custom [separator]).
String localizedDateTime(
  AppLocalizations l10n,
  DateTime value, {
  String separator = ' • ',
}) => '${localizedDate(l10n, value)}$separator${localizedTime(l10n, value)}';

/// `Today, 1:14 PM`, `Yesterday, 9:02 AM`, otherwise `18 Oct 2026, 1:14 PM`.
String localizedRelativeDateTime(
  AppLocalizations l10n,
  DateTime value, {
  DateTime? now,
}) {
  final local = value.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final todayStart = DateTime(today.year, today.month, today.day);
  final days = todayStart.difference(day).inDays;
  final time = localizedTime(l10n, local);
  return switch (days) {
    0 => l10n.relativeToday(time),
    1 => l10n.relativeYesterday(time),
    -1 => l10n.relativeTomorrow(time),
    _ => l10n.dateWithTime(localizedDate(l10n, local), time),
  };
}

/// A stored payment method (`cash`, `digital`, `credit`, `other`, `Split`,
/// `Unknown`) as the shop calls it. Unknown values are humanized, as before.
String localizedPaymentMethod(AppLocalizations l10n, String method) =>
    switch (method.toLowerCase()) {
      'cash' => l10n.paymentCash,
      'digital' => l10n.paymentDigital,
      'credit' => l10n.paymentUdhaar,
      'other' || 'split' => l10n.paymentSplit,
      'unknown' || '' => l10n.paymentNone,
      _ => humanizeIdentifier(method),
    };

String localizedWholeUnit(AppLocalizations l10n, MeasureUnit unit) =>
    switch (unit) {
      MeasureUnit.kg => l10n.unitKg,
      MeasureUnit.liter => l10n.unitLiter,
    };

String localizedFractionUnit(AppLocalizations l10n, MeasureUnit unit) =>
    switch (unit) {
      MeasureUnit.kg => l10n.unitGram,
      MeasureUnit.liter => l10n.unitMilliliter,
    };

/// `250 g`, `1.25 kg`, `750 ml`, `1.5 L` (`250 گرام`, `1.25 کلو` in Urdu).
/// Same thresholds as `formatMeasureQuantity`.
String localizedMeasureQuantity(
  AppLocalizations l10n,
  int thousandths,
  MeasureUnit unit,
) {
  final sign = thousandths < 0 ? '-' : '';
  final absolute = thousandths.abs();
  return absolute < 1000
      ? l10n.measureQuantity(
          '$sign$absolute',
          localizedFractionUnit(l10n, unit),
        )
      : l10n.measureQuantity(
          '$sign${formatDisplayQuantity(absolute)}',
          localizedWholeUnit(l10n, unit),
        );
}

/// A sale-line quantity: measured with its unit, otherwise a count.
String localizedLineQuantity(
  AppLocalizations l10n,
  int thousandths,
  MeasureUnit? unit,
) => unit == null
    ? formatDisplayQuantity(thousandths)
    : localizedMeasureQuantity(l10n, thousandths, unit);

/// `Rs 130.00/kg` / `Rs 130.00 فی کلو`; [formattedPrice] is already formatted.
String localizedUnitPrice(
  AppLocalizations l10n,
  String formattedPrice,
  MeasureUnit unit,
) => l10n.unitPrice(formattedPrice, localizedWholeUnit(l10n, unit));
