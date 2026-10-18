enum ShopRole { owner, cashier }

enum DeviceType { androidTablet, windowsDesktop, mobile, other }

enum SubscriptionPlan { trial, basic, pro, enterprise }

enum SubscriptionStatus { trial, active, pastDue, suspended, cancelled }

enum InventoryMovementType {
  openingStock,
  purchase,
  sale,
  returnIn,
  damage,
  manualAdjustment,
  stockCorrection,
}

/// How a product is sold (U1). Stored by name; never changes after creation.
enum SellMode { piece, measured }

/// Unit of a measured product. The stored quantity is thousandths of it:
/// grams for [kg], millilitres for [liter].
enum MeasureUnit {
  kg('kg', 'g'),
  liter('L', 'ml');

  const MeasureUnit(this.wholeLabel, this.fractionLabel);
  final String wholeLabel;
  final String fractionLabel;

  static MeasureUnit? tryParse(String? value) => switch (value) {
    'kg' => MeasureUnit.kg,
    'liter' => MeasureUnit.liter,
    _ => null,
  };
}

enum PaymentMethod { cash, digital, credit, other }

enum PaymentStatus { unpaid, partiallyPaid, paid, refunded }

enum SaleStatus { completed, voided, partiallyReturned, returned }

enum CustomerLedgerType {
  openingBalance,
  creditSale,
  paymentReceived,
  refund,
  adjustment,
}

enum SupplierLedgerType {
  openingBalance,
  purchase,
  paymentMade,
  refund,
  adjustment,
}

enum ShiftStatus { open, closed }

/// Outbox states (design §H). `failed` is the retry-wait state: the operation
/// is retried after its backoff. `needsAttention` (permanent rejection or
/// exhausted unknown errors) and `blockedAuth` (device/cashier no longer
/// authorised) are never retried automatically; the owner retries them.
enum SyncStatus {
  pending,
  syncing,
  synced,
  failed,
  needsAttention,
  blockedAuth,
}

enum SyncOperationType { create, update, delete }

extension InventoryMovementSign on InventoryMovementType {
  int? get conventionalSign => switch (this) {
    InventoryMovementType.openingStock ||
    InventoryMovementType.purchase ||
    InventoryMovementType.returnIn => 1,
    InventoryMovementType.sale || InventoryMovementType.damage => -1,
    InventoryMovementType.manualAdjustment ||
    InventoryMovementType.stockCorrection => null,
  };
}

extension CustomerLedgerSign on CustomerLedgerType {
  int get balanceSign => switch (this) {
    CustomerLedgerType.openingBalance ||
    CustomerLedgerType.creditSale ||
    CustomerLedgerType.adjustment => 1,
    CustomerLedgerType.paymentReceived || CustomerLedgerType.refund => -1,
  };
}

extension SupplierLedgerSign on SupplierLedgerType {
  int get balanceSign => switch (this) {
    SupplierLedgerType.openingBalance ||
    SupplierLedgerType.purchase ||
    SupplierLedgerType.adjustment => 1,
    SupplierLedgerType.paymentMade || SupplierLedgerType.refund => -1,
  };
}
