import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import 'pos_catalog.dart';
import 'pos_state.dart';

final class DriftPosCatalog implements PosCatalog {
  DriftPosCatalog(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  @override
  Future<PosCatalogSnapshot> load() async {
    final categories =
        await (db.select(db.categories)..where(
              (row) =>
                  row.isActive.equals(true) &
                  (row.shopId.equals(shopId) | row.shopId.isNull()),
            ))
            .get();
    final products = await db
        .customSelect(
          '''select sp.id,coalesce(sp.custom_name,mp.name,'Unnamed product') name,
      coalesce(sp.barcode,mp.barcode) barcode,coalesce(sp.category_id,mp.category_id) category_id,
      coalesce(sp.image_path,mp.default_image_path) image_path,sp.sale_price,
      sp.stock_tracking_enabled,sp.low_stock_level,coalesce(sum(im.quantity),0) stock
      from shop_products sp left join master_products mp on mp.id=sp.master_product_id
      left join inventory_movements im on im.shop_id=sp.shop_id and im.product_id=sp.id
      where sp.shop_id=? and sp.is_active=1 group by sp.id order by name limit 5000''',
          variables: [Variable(shopId)],
        )
        .get();
    final customers = await db
        .customSelect(
          '''select c.id,c.name,c.credit_limit,
      coalesce(sum(case when l.type in ('openingBalance','creditSale','adjustment')
      then l.amount else -l.amount end),0) balance from customers c
      left join customer_ledger_entries l on l.shop_id=c.shop_id and l.customer_id=c.id
      where c.shop_id=? and c.is_active=1 group by c.id order by c.name limit 1000''',
          variables: [Variable(shopId)],
        )
        .get();

    return PosCatalogSnapshot(
      categories: categories
          .map((row) => PosCategory(id: row.id, name: row.name))
          .toList(),
      products: products.map((result) {
        final row = result.data;
        return PosProduct(
          id: row['id'] as String,
          name: row['name'] as String,
          barcode: row['barcode'] as String?,
          categoryId: row['category_id'] as String?,
          imagePath: row['image_path'] as String?,
          salePriceMinor: row['sale_price'] as int,
          stockQuantity: row['stock'] as int,
          stockTrackingEnabled: (row['stock_tracking_enabled'] as int) != 0,
          lowStockLevel: row['low_stock_level'] as int?,
        );
      }).toList(),
      customers: customers
          .map(
            (result) => PosCustomer(
              id: result.data['id'] as String,
              name: result.data['name'] as String,
              balanceMinor: result.data['balance'] as int,
              creditLimitMinor: result.data['credit_limit'] as int?,
            ),
          )
          .toList(),
    );
  }
}
