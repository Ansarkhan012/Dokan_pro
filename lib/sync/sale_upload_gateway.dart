abstract interface class SaleUploadGateway {
  /// Uploads one queued operation and completes with the RPC result (a JSON
  /// object such as `{"status": "accepted_flagged", "flags": [...]}`), or
  /// null when the transport has none. Throws when the server rejects it.
  Future<Object?> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  });
}

/// Record-and-flag rule codes in an upload result (design §I): non-empty when
/// the server accepted the operation but flagged it for the owner, including
/// on a replay that answers `already_synced`.
List<String> serverFlagsOf(Object? result) {
  if (result case {'flags': final List<Object?> flags}) {
    return [
      for (final flag in flags)
        if (flag != null) flag.toString(),
    ];
  }
  return const [];
}
