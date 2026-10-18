/// Shop-owner facing formatting. Presentation only: never parse these back
/// and never use them as identities, keys or sync payloads.
library;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `5 Oct 2026` in device-local time.
String formatDisplayDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `1:17 PM` in device-local time.
String formatDisplayTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// `5 Oct 2026 • 1:17 PM` (or with a custom [separator]).
String formatDisplayDateTime(DateTime value, {String separator = ' • '}) =>
    '${formatDisplayDate(value)}$separator${formatDisplayTime(value)}';

/// `Today, 1:14 PM`, `Yesterday, 9:02 AM`, otherwise `18 Oct 2026, 1:14 PM`.
String formatRelativeDateTime(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final todayStart = DateTime(today.year, today.month, today.day);
  final days = todayStart.difference(day).inDays;
  final time = formatDisplayTime(local);
  if (days == 0) return 'Today, $time';
  if (days == 1) return 'Yesterday, $time';
  if (days == -1) return 'Tomorrow, $time';
  return '${formatDisplayDate(local)}, $time';
}

/// Payment method as stored (`cash`, `digital`, `credit`, `other`, `Split`,
/// `Unknown`) to the label the shop uses.
String paymentMethodLabel(String method) => switch (method.toLowerCase()) {
  'cash' => 'Cash',
  'digital' => 'Digital',
  'credit' => 'Udhaar',
  'other' || 'split' => 'Split',
  'unknown' || '' => 'No payment',
  _ => _humanize(method),
};

/// `pilot_basic` / `trialPlan` → `Pilot basic` / `Trial plan`.
String humanizeIdentifier(String value) => _humanize(value);

String _humanize(String value) {
  final spaced = value
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim()
      .toLowerCase();
  if (spaced.isEmpty) return value;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Stored quantity (thousandths) for display: `12000` → `12`, `1500` → `1.5`.
String formatDisplayQuantity(int scaled) {
  final sign = scaled < 0 ? '-' : '';
  final absolute = scaled.abs();
  final whole = absolute ~/ 1000, fraction = absolute % 1000;
  if (fraction == 0) return '$sign$whole';
  final digits = fraction
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '$sign$whole.$digits';
}

/// Signed movement quantity: `+39`, `-2`, `0`.
String formatSignedQuantity(int scaled) => scaled > 0
    ? '+${formatDisplayQuantity(scaled)}'
    : formatDisplayQuantity(scaled);
