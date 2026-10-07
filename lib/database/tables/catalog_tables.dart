import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import 'organization_tables.dart';

@TableIndex(name: 'categories_shop_id', columns: {#shopId})
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().nullable().references(Shops, #id)();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'master_products_barcode', columns: {#barcode})
class MasterProducts extends Table {
  TextColumn get id => text()();
  TextColumn get barcode => text().unique()();
  TextColumn get name => text()();
  TextColumn get brand => text()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get defaultImagePath => text().nullable()();
  TextColumn get defaultUnit => text()();
  TextColumn get packLabel => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'shop_products_shop_id', columns: {#shopId})
@TableIndex(name: 'shop_products_barcode', columns: {#shopId, #barcode})
class ShopProducts extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text().references(Shops, #id)();
  TextColumn get masterProductId =>
      text().nullable().references(MasterProducts, #id)();
  TextColumn get customName => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get unit => text().nullable()();
  TextColumn get packLabel => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  IntColumn get purchasePrice => integer()();
  IntColumn get salePrice => integer()();
  BoolColumn get stockTrackingEnabled =>
      boolean().withDefault(const Constant(true))();
  IntColumn get lowStockLevel => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // U1 (v13). `piece` (every pre-v13 product) or `measured` (unit kg/liter).
  // Fixed at creation; quantities stay thousandths of [unit] either way.
  TextColumn get sellMode =>
      text().withDefault(Constant(SellMode.piece.name))();

  /// Pack variants of one product share it. Grouping only, never sellable.
  TextColumn get familyId => text().nullable()();

  /// Measured quick quantities in thousandths, as a JSON array; null means
  /// the defaults.
  TextColumn get measurePresets => text().nullable()();
  BoolColumn get allowCustomQuantity =>
      boolean().withDefault(const Constant(true))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
