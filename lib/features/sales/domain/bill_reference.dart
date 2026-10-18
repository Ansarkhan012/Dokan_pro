/// Cashier-facing bill reference for a sale.
///
/// Presentation only: the sale UUID stays the primary, idempotency and sync
/// identity and is never rewritten. A stored invoice number wins when one
/// exists; otherwise the reference is the last eight characters of the
/// UUID. For UUIDv7 those come from the random tail, so the code is stable on
/// every device without a counter, unlike the time-ordered prefix.
String billReference(String saleId, {String? invoiceNumber}) {
  final invoice = invoiceNumber?.trim();
  if (invoice != null && invoice.isNotEmpty) return 'Bill #$invoice';
  return 'Bill #${billCode(saleId)}';
}

const _billCodeLength = 8;

String billCode(String saleId) {
  final compact = saleId.replaceAll('-', '').toUpperCase();
  return compact.length <= _billCodeLength
      ? compact
      : compact.substring(compact.length - _billCodeLength);
}

/// The bill code a cashier typed into search (`Bill #0509F516`, `#0509f516`,
/// `0509F516`), lower-cased for matching the UUID tail, or null.
String? searchedBillCode(String query) {
  final code = query
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^bill\s*'), '')
      .replaceFirst('#', '')
      .trim();
  return RegExp('^[0-9a-f]{$_billCodeLength}\$').hasMatch(code) ? code : null;
}
