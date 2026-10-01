enum PullEntity {
  shops,
  devices,
  cashiers,
  categories,
  masterProducts,
  shopProducts,
  customers,
  customerLedgerEntries,
  suppliers,
  supplierLedgerEntries,
  purchases,
  purchaseItems,
  purchasePayments,
  expenseCategories,
  expenses,
  inventoryMovements,
  sales,
  saleItems,
  salePayments,
  saleReturns,
  saleReturnItems,
  saleVoids,

  /// Categories shared by every shop (no shop id). They are numbered by the
  /// server's global counter, so they keep a cursor of their own; pulling
  /// [categories] pulls both streams.
  globalCategories,
}

/// Position of the last applied row. Since R1.4 the authoritative position
/// is the server-assigned (serverSeq, entityId); [updatedAt] is informational.
final class PullCursor {
  const PullCursor({
    required this.updatedAt,
    required this.entityId,
    this.serverSeq = -1,
  });
  final DateTime updatedAt;
  final String entityId;
  final int serverSeq;
}

final class RemoteChange {
  const RemoteChange({
    required this.entity,
    required this.id,
    required this.updatedAt,
    required this.data,
    this.shopId,
    this.serverSeq = 0,
  });
  final PullEntity entity;
  final String id;
  final String? shopId;
  final DateTime updatedAt;

  /// The row's server-assigned sync position (R1.4).
  final int serverSeq;
  final Map<String, dynamic> data;
}
