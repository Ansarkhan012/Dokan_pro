import 'package:drift/drift.dart';

/// The one encoding of an instant that leaves the device (R1.2, finding T-1).
///
/// Drift reads stored date-times back as *local* `DateTime`s, and Drift's
/// default string serializer writes them with `toIso8601String()`, i.e. the
/// device's wall clock with no offset. The server then read that wall clock
/// as UTC and every sale/purchase moved by the device's UTC offset.
abstract final class SyncTime {
  /// RFC 3339 UTC ending in `Z`. [instant] may be held as local or UTC time;
  /// it is converted as an instant, never relabelled.
  static String encode(DateTime instant) => instant.toUtc().toIso8601String();

  /// Whether [text] states its offset (`Z` or `±hh:mm` / `±hhmm`).
  static bool hasExplicitOffset(String text) => _explicitOffset.hasMatch(text);

  /// Serializer for Drift rows written into outbox payloads: date-times use
  /// [encode]; every other value is encoded exactly as before.
  static const ValueSerializer payloadSerializer = _PayloadSerializer();

  static final _explicitOffset = RegExp(r'(Z|[+-]\d\d:?\d\d)$');
}

final class _PayloadSerializer extends ValueSerializer {
  const _PayloadSerializer();

  static const _drift = ValueSerializer.defaults(
    serializeDateTimeValuesAsString: true,
  );

  @override
  dynamic toJson<T>(T value) =>
      value is DateTime ? SyncTime.encode(value) : _drift.toJson<T>(value);

  @override
  T fromJson<T>(dynamic json) => _drift.fromJson<T>(json);
}
