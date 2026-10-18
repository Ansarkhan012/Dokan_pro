import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sale_payload_codec.dart';

/// How a failed upload is handled (design §H, decision D4).
enum SyncFailureKind {
  /// No response (offline, DNS, socket, timeout). Retried without limit.
  connectivity,

  /// The server answered with a known retryable failure. Retried without limit.
  transient,

  /// Device, cashier or session not authorised. Waits for a new session or
  /// an owner retry; never retried on a timer.
  auth,

  /// Cannot succeed by retrying unchanged. Needs attention immediately.
  permanent,

  /// Anything else. Retried a bounded number of times, then needs attention.
  unknown,
}

/// A server error carrying a stable code (a SQLSTATE such as `DPV01`).
/// Implemented by non-PostgREST transports (e.g. the direct-DB harness).
abstract interface class SyncCodedError {
  String? get code;
}

final class SyncFailure {
  const SyncFailure(this.kind, {this.code, required this.reason});
  final SyncFailureKind kind;

  /// Stable code; null only for transport failures without one.
  final String? code;

  /// Safe for the owner: no SQL, payload or server internals.
  final String reason;
}

/// Stable server codes. Only these codes, never message text, decide that an
/// operation is permanent.
const _permanent = {
  'DPV01': 'The cloud rejected this record as invalid or out of date.',
  'DPC01': 'A different version of this record is already in the cloud.',
  'DPX01': 'This change conflicts with the cloud and cannot be applied.',
};
const _auth = {
  'DPA01': 'This device or cashier is no longer authorised.',
  '42501': 'This device or session is not authorised to sync.',
  'PGRST301': 'The sign-in session expired.',
  'PGRST302': 'The sign-in session is missing.',
  '401': 'The sign-in session expired.',
  '403': 'This device or session is not authorised to sync.',
};
const _transientSqlStates = {
  '40001', // serialization failure
  '40P01', // deadlock
  '55P03', // lock not available
  '57014', // statement timeout / cancelled
};

SyncFailure classifySyncError(Object error) {
  if (error is AmbiguousTimestampPayload) {
    return const SyncFailure(
      SyncFailureKind.permanent,
      code: 'legacy_timestamp_payload',
      reason:
          'This record was saved by an older app version and cannot be '
          'sent safely.',
    );
  }
  if (error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException ||
      error is http.ClientException ||
      error is AuthRetryableFetchException) {
    return const SyncFailure(
      SyncFailureKind.connectivity,
      reason: 'No connection to the cloud. It will retry automatically.',
    );
  }
  final code = switch (error) {
    PostgrestException(:final code) => code,
    SyncCodedError(:final code) => code,
    _ => null,
  };
  if (code != null) {
    if (_permanent[code] case final reason?) {
      return SyncFailure(SyncFailureKind.permanent, code: code, reason: reason);
    }
    if (_auth[code] case final reason?) {
      return SyncFailure(SyncFailureKind.auth, code: code, reason: reason);
    }
    final status = int.tryParse(code);
    if (_transientSqlStates.contains(code) ||
        code.startsWith('08') || // connection exception
        code.startsWith('53') || // insufficient resources
        code.startsWith('57P') || // server shutting down
        status == 408 ||
        status == 429 ||
        (status != null && status >= 500 && status <= 599)) {
      return SyncFailure(
        SyncFailureKind.transient,
        code: code,
        reason:
            'The cloud is temporarily unavailable. It will retry '
            'automatically.',
      );
    }
  }
  return SyncFailure(
    SyncFailureKind.unknown,
    code: code ?? 'unknown_error',
    reason: 'The cloud could not accept this record.',
  );
}
