import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import 'organization_tables.dart';

@TableIndex(name: 'expense_categories_shop_name', columns: {#shopId, #name})
class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'expenses_shop_created', columns: {#shopId, #createdAt})
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get category => text()();
  TextColumn get categoryId =>
      text().nullable().references(ExpenseCategories, #id)();
  IntColumn get amount => integer()();
  TextColumn get paymentMethod => textEnum<PaymentMethod>().withDefault(
    Constant(PaymentMethod.cash.name),
  )();
  TextColumn get description => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get deviceId => text().nullable().references(Devices, #id)();
  DateTimeColumn get expenseAt => dateTime().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'shifts_shop_cashier',
  columns: {#shopId, #cashierId, #openedAt},
)
class CashierShifts extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get cashierId => text()();
  TextColumn get deviceId => text().references(Devices, #id)();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get openingCash => integer()();
  IntColumn get expectedCash => integer().nullable()();
  IntColumn get actualCash => integer().nullable()();
  IntColumn get cashDifference => integer().nullable()();
  TextColumn get status => textEnum<ShiftStatus>()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'audit_shop_created', columns: {#shopId, #createdAt})
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get userId => text()();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get deviceId => text().nullable().references(Devices, #id)();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'sync_queue_status_created',
  columns: {#shopId, #status, #createdAt},
)
@TableIndex(
  name: 'sync_queue_entity',
  columns: {#shopId, #entityType, #entityId},
)
class SyncOperations extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get deviceId => text().references(Devices, #id)();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operationType => textEnum<SyncOperationType>()();
  TextColumn get payload => text()();
  TextColumn get status =>
      textEnum<SyncStatus>().withDefault(Constant(SyncStatus.pending.name))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  TextColumn get leaseOwner => text().nullable()();
  DateTimeColumn get leaseExpiresAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get dependsOnOperationId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncCursors extends Table {
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get entityType => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get entityId => text()();

  /// Server-assigned sync position of the last applied row (v11, R1.4).
  /// Null for a cursor written before v11, which is not a safe position.
  IntColumn get serverSeq => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {shopId, entityType};
}
