import 'sync_time.dart';

/// A queued payload holds a timestamp without a UTC offset. Payloads queued
/// before R1.2 wrote the device's local wall clock that way, so the instant
/// cannot be known from the payload: it is never guessed, rewritten or
/// uploaded, and the operation stays failed with this error until an
/// approved reconciliation path handles it.
final class AmbiguousTimestampPayload implements Exception {
  const AmbiguousTimestampPayload(this.path, this.value);
  final String path;
  final String value;
  @override
  String toString() =>
      'AmbiguousTimestampPayload: $path="$value" has no UTC offset '
      '(queued before R1.2); not uploaded';
}

/// The payload exactly as it is sent to the server, for every operation.
/// Throws [AmbiguousTimestampPayload] instead of sending an offset-less
/// timestamp, which the server would read as UTC.
Map<String, dynamic> payloadForCloud(Map<String, dynamic> payload) {
  if (payload['operation'] == 'sync_sale_transaction') {
    return normalizeSalePayloadForCloud(payload);
  }
  _rejectAmbiguous(payload, r'$');
  return payload;
}

/// Converts queued sale timestamps into the format PostgreSQL expects,
/// preserving each instant.
///
/// Older queued operations contain epoch milliseconds because that is Drift's
/// default JSON representation; those are unambiguous instants. Strings must
/// carry an explicit offset (every payload built since R1.2 ends in `Z`).
Map<String, dynamic> normalizeSalePayloadForCloud(
  Map<String, dynamic> payload,
) {
  final normalized = _normalizeMap(payload, r'$');
  _rejectAmbiguous(normalized, r'$');
  return normalized;
}

Map<String, dynamic> _normalizeMap(Map<String, dynamic> value, String path) => {
  for (final entry in value.entries)
    entry.key: _normalizeValue(entry.key, entry.value, '$path.${entry.key}'),
};

Object? _normalizeValue(String key, Object? value, String path) {
  final timestamp = key == 'createdAt' || key == 'syncedAt';
  if (timestamp && value is int) {
    return SyncTime.encode(
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
    );
  }
  if (timestamp && value is String) {
    if (!SyncTime.hasExplicitOffset(value)) {
      throw AmbiguousTimestampPayload(path, value);
    }
    return SyncTime.encode(DateTime.parse(value));
  }
  if (value is Map<String, dynamic>) return _normalizeMap(value, path);
  if (value is List) {
    return [
      for (var i = 0; i < value.length; i++)
        value[i] is Map<String, dynamic>
            ? _normalizeMap(value[i] as Map<String, dynamic>, '$path[$i]')
            : value[i],
    ];
  }
  return value;
}

final _isoDateTime = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

void _rejectAmbiguous(Object? value, String path) {
  if (value is Map) {
    value.forEach((key, item) => _rejectAmbiguous(item, '$path.$key'));
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _rejectAmbiguous(value[i], '$path[$i]');
    }
  } else if (value is String &&
      _isoDateTime.hasMatch(value) &&
      !SyncTime.hasExplicitOffset(value)) {
    throw AmbiguousTimestampPayload(path, value);
  }
}
