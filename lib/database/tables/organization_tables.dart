import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';

class Shops extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  TextColumn get address => text()();
  TextColumn get currency => text().withDefault(const Constant('PKR'))();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Karachi'))();
  BoolColumn get allowNegativeStock =>
      boolean().withDefault(const Constant(true))();
  IntColumn get defaultLowStockLevel =>
      integer().withDefault(const Constant(0))();
  TextColumn get receiptFooter => text().withDefault(const Constant(''))();
  TextColumn get receiptPaperWidth =>
      text().withDefault(const Constant('80mm'))();
  BoolColumn get receiptShowPhone =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get receiptShowAddress =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get notificationsEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get subscriptionPlan => textEnum<SubscriptionPlan>()();
  TextColumn get subscriptionStatus => textEnum<SubscriptionStatus>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local cashier identity metadata. PIN material is verified and stored only by
/// the backend; the offline database never stores a plaintext PIN or hash.
@TableIndex(name: 'cashiers_shop_id', columns: {#shopId})
class Cashiers extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get displayName => text()();
  TextColumn get loginCode => text()();
  IntColumn get credentialVersion => integer().withDefault(const Constant(1))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {shopId, loginCode},
  ];
}

@TableIndex(name: 'shop_users_shop_id', columns: {#shopId})
class ShopUsers extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get userId => text()();
  TextColumn get role => textEnum<ShopRole>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {shopId, userId},
  ];
}

@TableIndex(name: 'devices_shop_id', columns: {#shopId})
class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get deviceName => text()();
  TextColumn get deviceType => textEnum<DeviceType>()();
  TextColumn get deviceIdentifier => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column<Object>> get primaryKey => {id};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {shopId, deviceIdentifier},
  ];
}
