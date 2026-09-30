import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import 'catalog_tables.dart';
import 'organization_tables.dart';
import 'party_tables.dart';

@TableIndex(name: 'sales_shop_created', columns: {#shopId, #createdAt})
@TableIndex(name: 'sales_shop_invoice', columns: {#shopId, #invoiceNumber})
class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get cashierId => text()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get deviceId => text().references(Devices, #id)();
  TextColumn get invoiceNumber => text().nullable()();
  IntColumn get subtotal => integer()();
  IntColumn get discountTotal => integer()();
  IntColumn get taxTotal => integer()();
  IntColumn get grandTotal => integer()();
  TextColumn get paymentStatus => textEnum<PaymentStatus>()();
  TextColumn get saleStatus => textEnum<SaleStatus>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'sale_items_sale_id', columns: {#saleId})
@TableIndex(name: 'sale_items_product_id', columns: {#shopId, #productId})
class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(ShopProducts, #id)();
  TextColumn get productNameSnapshot => text()();
  TextColumn get barcodeSnapshot => text().nullable()();
  IntColumn get quantity => integer()();
  IntColumn get costPriceSnapshot => integer()();
  IntColumn get salePriceSnapshot => integer()();
  IntColumn get discountAmount => integer()();
  IntColumn get lineTotal => integer()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'sale_payments_sale_id', columns: {#saleId})
class SalePayments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get paymentMethod => textEnum<PaymentMethod>()();
  IntColumn get amount => integer()();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'sale_returns_original', columns: {#shopId, #originalSaleId})
class SaleReturns extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get originalSaleId => text().references(Sales, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get deviceId => text().references(Devices, #id)();
  TextColumn get refundMethod => textEnum<PaymentMethod>()();
  IntColumn get refundAmount => integer()();
  TextColumn get reason => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'sale_return_items_return', columns: {#returnId})
@TableIndex(
  name: 'sale_return_items_original_item',
  columns: {#shopId, #originalSaleItemId},
)
class SaleReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get returnId => text().references(SaleReturns, #id)();
  TextColumn get originalSaleItemId => text().references(SaleItems, #id)();
  TextColumn get productId => text().references(ShopProducts, #id)();
  TextColumn get productNameSnapshot => text()();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceSnapshot => integer()();
  IntColumn get refundAmount => integer()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'sale_voids_original', columns: {#shopId, #originalSaleId})
class SaleVoids extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get originalSaleId => text().references(Sales, #id)();
  TextColumn get deviceId => text().references(Devices, #id)();
  IntColumn get amount => integer()();
  TextColumn get reason => text()();
  TextColumn get paymentBreakdown => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'inventory_product_created',
  columns: {#shopId, #productId, #createdAt},
)
class InventoryMovements extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get productId => text().references(ShopProducts, #id)();
  TextColumn get type => textEnum<InventoryMovementType>()();
  IntColumn get quantity => integer()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get deviceId => text().nullable().references(Devices, #id)();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'purchases_shop_created', columns: {#shopId, #createdAt})
class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get deviceId => text().nullable().references(Devices, #id)();
  TextColumn get invoiceNumber => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get subtotal => integer()();
  IntColumn get discountTotal => integer()();
  IntColumn get total => integer()();
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();
  TextColumn get paymentStatus => textEnum<PaymentStatus>()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'purchase_items_purchase_id', columns: {#purchaseId})
class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get productId => text().references(ShopProducts, #id)();
  TextColumn get productNameSnapshot =>
      text().withDefault(const Constant(''))();
  IntColumn get quantity => integer()();
  IntColumn get unitCost => integer()();
  IntColumn get lineTotal => integer()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'purchase_payments_purchase_id', columns: {#purchaseId})
class PurchasePayments extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get paymentMethod => textEnum<PaymentMethod>()();
  IntColumn get amount => integer()();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
