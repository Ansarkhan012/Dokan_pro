import 'dart:convert';

import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/format/measure_format.dart';
import '../../core/l10n/product_display_names.dart';
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
    ProductListStatus status = ProductListStatus.all,
  }) async {
    final pattern = '%${query.trim().toLowerCase()}%';
    // An Urdu query matches through the offline Urdu display names, which
    // SQL cannot see: resolve those products first, by id.
    final urduIds = hasUrduScript(query)
        ? await _idsMatchingUrduName(query)
        : const <String>[];
    final urduClause = urduIds.isEmpty
        ? ''
        : ' or sp.id in (${List.filled(urduIds.length, '?').join(',')})';
    final rows = await db
        .customSelect(
          '''select sp.id,coalesce(sp.custom_name,mp.name,'Unnamed product') name,
      coalesce(c.name,'Uncategorized') category_name,c.id category_id,coalesce(sp.barcode,mp.barcode) barcode,
      coalesce(sp.unit,mp.default_unit,'piece') unit,coalesce(sp.pack_label,mp.pack_label) pack_label,
      coalesce(sp.image_path,mp.default_image_path) image_path,sp.purchase_price,sp.sale_price,
      sp.low_stock_level,sp.is_active,sp.master_product_id,coalesce(sum(im.quantity),0) stock,
      sp.sell_mode,sp.measure_presets,sp.allow_custom_quantity,sp.family_id,
      count(im.id) movement_count
      from shop_products sp left join master_products mp on mp.id=sp.master_product_id
      left join categories c on c.id=coalesce(sp.category_id,mp.category_id)
      left join inventory_movements im on im.shop_id=sp.shop_id and im.product_id=sp.id
      where sp.shop_id=? and (?='' or lower(coalesce(sp.custom_name,mp.name,'')) like ?
        or coalesce(sp.barcode,mp.barcode)=?
        or (sp.family_id is not null and replace(lower(coalesce(sp.custom_name,'')||coalesce(sp.pack_label,'')),' ','') like ?)$urduClause)
        and (? is null or coalesce(c.name,'Uncategorized')=?)
        and (? is null or sp.is_active=?)
      group by sp.id order by name limit ? offset ?''',
          variables: [
            Variable(shopId),
            Variable(query.trim()),
            Variable(pattern),
            Variable(query.trim()),
            // U3: "500g" finds a "500 g" pack variant (spaces ignored).
            Variable('%${query.trim().toLowerCase().replaceAll(' ', '')}%'),
            for (final id in urduIds) Variable(id),
            Variable(category),
            Variable(category),
            Variable(_activeFilter(status)),
            Variable(_activeFilter(status)),
            Variable(limit),
            Variable(offset),
          ],
        )
        .get();
    return rows.map((result) {
      final row = result.data;
      return ManagedProduct(
        id: row['id'] as String,
        // U3: a pack variant reads as its family name plus the pack size.
        name: sellableName(
          row['name'] as String,
          row['pack_label'] as String?,
          familyId: row['family_id'] as String?,
        ),
        baseName: row['name'] as String,
        movementCount: row['movement_count'] as int,
        familyId: row['family_id'] as String?,
        categoryName: row['category_name'] as String,
        categoryId: row['category_id'] as String?,
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

  static int? _activeFilter(ProductListStatus status) => switch (status) {
    ProductListStatus.all => null,
    ProductListStatus.active => 1,
    ProductListStatus.archived => 0,
  };

  /// Every record that refers to [productId] on this device. Read only.
  Future<ProductUsage> usage(String productId) async {
    Future<int> count(String table) async =>
        (await db
                .customSelect(
                  'select count(*) n from $table where shop_id=? and product_id=?',
                  variables: [Variable(shopId), Variable(productId)],
                )
                .getSingle())
            .read<int>('n');
    return ProductUsage(
      saleLines: await count('sale_items'),
      purchaseLines: await count('purchase_items'),
      returnLines: await count('sale_return_items'),
      movements: await count('inventory_movements'),
    );
  }

  Future<List<String>> _idsMatchingUrduName(String query) async {
    final rows = await db
        .customSelect(
          '''select sp.id,coalesce(sp.custom_name,mp.name,'') name
      from shop_products sp left join master_products mp on mp.id=sp.master_product_id
      where sp.shop_id=?''',
          variables: [Variable(shopId)],
        )
        .get();
    return [
      for (final row in rows)
        if (ProductDisplayNameResolver.instance.matches(
          row.data['name'] as String,
          query,
          productId: row.data['id'] as String,
        ))
          row.data['id'] as String,
    ];
  }

  /// Mirrors an edit the server has already accepted, so the lists show it
  /// at once; the next reference pull writes the same values. Never touches
  /// stock, selling mode or any history.
  Future<void> applyAcceptedEdit(
    ManagedProduct product,
    ProductEdit edit,
  ) => db.transaction(() async {
    await (db.update(
      db.shopProducts,
    )..where((t) => t.shopId.equals(shopId) & t.id.equals(product.id))).write(
      ShopProductsCompanion(
        purchasePrice: Value(edit.purchasePriceMinor),
        salePrice: Value(edit.salePriceMinor),
        lowStockLevel: Value(edit.lowStockLevel),
        isActive: Value(edit.isActive),
        barcode: edit.barcodeChanged
            ? Value(edit.barcode)
            : const Value.absent(),
        unit: edit.unit == null ? const Value.absent() : Value(edit.unit!.name),
        packLabel: edit.packLabelChanged
            ? Value(edit.packLabel)
            : const Value.absent(),
        measurePresets: edit.measurePresets == null
            ? const Value.absent()
            : Value(jsonEncode(edit.measurePresets)),
        allowCustomQuantity: edit.allowCustomQuantity == null
            ? const Value.absent()
            : Value(edit.allowCustomQuantity!),
        // Never for a pack variant: its name and category are shared by the
        // family, and the gateway refuses those edits (no atomic update).
        customName: edit.name == null || product.familyId != null
            ? const Value.absent()
            : Value(edit.name),
        categoryId: edit.categoryId == null || product.familyId != null
            ? const Value.absent()
            : Value(edit.categoryId),
      ),
    );
  });

  /// Mirrors an archive or restore the server has already accepted.
  Future<void> applyAcceptedActive(String productId, bool isActive) =>
      (db.update(db.shopProducts)
            ..where((t) => t.shopId.equals(shopId) & t.id.equals(productId)))
          .write(ShopProductsCompanion(isActive: Value(isActive)));
}
