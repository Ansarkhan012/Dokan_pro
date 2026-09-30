import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import 'organization_tables.dart';

@TableIndex(name: 'customers_shop_id', columns: {#shopId})
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get creditLimit => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'customer_ledger_lookup',
  columns: {#shopId, #customerId, #createdAt},
)
class CustomerLedgerEntries extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get type => textEnum<CustomerLedgerType>()();
  IntColumn get amount => integer()();
  TextColumn get saleId => text().nullable()();
  TextColumn get paymentReference => text().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'suppliers_shop_id', columns: {#shopId})
class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get name => text()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'supplier_ledger_lookup',
  columns: {#shopId, #supplierId, #createdAt},
)
class SupplierLedgerEntries extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get supplierId => text().references(Suppliers, #id)();
  TextColumn get type => textEnum<SupplierLedgerType>()();
  IntColumn get amount => integer()();
  TextColumn get purchaseId => text().nullable()();
  TextColumn get paymentReference => text().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
