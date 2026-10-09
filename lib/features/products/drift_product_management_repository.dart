import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/format/measure_format.dart';
import '../../database/app_database.dart';
import 'product_management_models.dart';

final class DriftProductManagementRepository {
  DriftProductManagementRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  Future<List<ProductCategory>> categories() async =>
      (await (db.select(db.categories)..where(
                (row) =>
                    row.isActive.equals(true) &
                    (row.shopId.equals(shopId) | row.shopId.isNull()),
              ))
              .get())
          .map((row) => ProductCategory(id: row.id, name: row.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  Future<List<ManagedProduct>> products({
    String query = '',
    String? category,
    int limit = 200,
    int offset = 0,
  }) async {
    final pattern = '%${query.trim().toLowerCase()}%';
    final rows = await db
        .customSelect(
          '''select sp.id,coalesce(sp.custom_name,mp.name,'Unnamed product') name,
      coalesce(c.name,'Uncategorized') category_name,coalesce(sp.barcode,mp.barcode) barcode,
      coalesce(sp.unit,mp.default_unit,'piece') unit,coalesce(sp.pack_label,mp.pack_label) pack_label,
      coalesce(sp.image_path,mp.default_image_path) image_path,sp.purchase_price,sp.sale_price,
      sp.low_stock_level,sp.is_active,sp.master_product_id,coalesce(sum(im.quantity),0) stock,
      sp.sell_mode,sp.measure_presets,sp.allow_custom_quantity
      from shop_products sp left join master_products mp on mp.id=sp.master_product_id
      left join categories c on c.id=coalesce(sp.category_id,mp.category_id)
      left join inventory_movements im on im.shop_id=sp.shop_id and im.product_id=sp.id
      where sp.shop_id=? and (?='' or lower(coalesce(sp.custom_name,mp.name,'')) like ?
        or coalesce(sp.barcode,mp.barcode)=?)
        and (? is null or coalesce(c.name,'Uncategorized')=?)
      group by sp.id order by name limit ? offset ?''',
          variables: [
            Variable(shopId),
            Variable(query.trim()),
            Variable(pattern),
            Variable(query.trim()),
            Variable(category),
            Variable(category),
            Variable(limit),
            Variable(offset),
          ],
        )
        .get();
    return rows.map((result) {
      final row = result.data;
      return ManagedProduct(
        id: row['id'] as String,
        name: row['name'] as String,
        categoryName: row['category_name'] as String,
        barcode: row['barcode'] as String?,
        unit: row['unit'] as String,
        packLabel: row['pack_label'] as String?,
        imagePath: row['image_path'] as String?,
        purchasePriceMinor: row['purchase_price'] as int,
        salePriceMinor: row['sale_price'] as int,
        stockQuantity: row['stock'] as int,
        lowStockLevel: row['low_stock_level'] as int?,
        isActive: (row['is_active'] as int) != 0,
        isCustom: row['master_product_id'] == null,
        sellMode: row['sell_mode'] == SellMode.measured.name
            ? SellMode.measured
            : SellMode.piece,
        measurePresets: decodeMeasurePresets(row['measure_presets'] as String?),
        allowCustomQuantity: (row['allow_custom_quantity'] as int) != 0,
      );
    }).toList();
  }
}
