/// Converts legacy Drift timestamp JSON into the format expected by PostgreSQL.
///
/// Older queued operations contain epoch milliseconds because that is Drift's
/// default JSON representation. Keeping this conversion at the upload boundary
/// lets those operations retry with their original operation and entity IDs.
Map<String, dynamic> normalizeSalePayloadForCloud(
  Map<String, dynamic> payload,
) => _normalizeMap(payload);

Map<String, dynamic> _normalizeMap(Map<String, dynamic> value) => {
  for (final entry in value.entries)
    entry.key: _normalizeValue(entry.key, entry.value),
};

Object? _normalizeValue(String key, Object? value) {
  final timestamp = key == 'createdAt' || key == 'syncedAt';
  if (timestamp && value is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      value,
      isUtc: true,
    ).toIso8601String();
  }
  if (timestamp && value is String) {
    final parsed = DateTime.parse(value);
    final utc = parsed.isUtc
        ? parsed
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
    return utc.toIso8601String();
  }
  if (value is Map<String, dynamic>) return _normalizeMap(value);
  if (value is List) {
    return value
        .map(
          (item) => item is Map<String, dynamic> ? _normalizeMap(item) : item,
        )
        .toList();
  }
  return value;
}
