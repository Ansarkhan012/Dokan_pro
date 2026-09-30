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
}

final class PullCursor {
  const PullCursor({required this.updatedAt, required this.entityId});
  final DateTime updatedAt;
  final String entityId;
}

final class RemoteChange {
  const RemoteChange({
    required this.entity,
    required this.id,
    required this.updatedAt,
    required this.data,
    this.shopId,
  });
  final PullEntity entity;
  final String id;
  final String? shopId;
  final DateTime updatedAt;
  final Map<String, dynamic> data;
}
