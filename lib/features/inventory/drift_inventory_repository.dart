import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../sales/domain/bill_reference.dart';
import 'inventory_models.dart';

final class DriftInventoryRepository {
  DriftInventoryRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  Future<List<InventoryProductRow>> products({
    String search = '',
    InventoryFilter filter = InventoryFilter.all,
  }) async {
    final query = search.trim().toLowerCase();
    final rows = await db
        .customSelect(
          '''select sp.id, coalesce(sp.custom_name,mp.name,'Unnamed product') name,
      coalesce(sp.unit,mp.default_unit,'piece') unit,
      coalesce(sp.barcode,mp.barcode) barcode,sp.low_stock_level,sp.is_active,
      coalesce(sp.image_path,mp.default_image_path) image_path,
      coalesce(sum(im.quantity),0) stock
      from shop_products sp left join master_products mp on mp.id=sp.master_product_id
      left join inventory_movements im on im.shop_id=sp.shop_id and im.product_id=sp.id
      where sp.shop_id=? group by sp.id order by name''',
          variables: [Variable(shopId)],
        )
        .get();
    return rows
        .map((result) {
          final row = result.data;
          return InventoryProductRow(
            id: row['id'] as String,
            name: row['name'] as String,
            unit: row['unit'] as String,
            barcode: row['barcode'] as String?,
            imagePath: row['image_path'] as String?,
            stockQuantity: row['stock'] as int,
            lowStockLevel: row['low_stock_level'] as int?,
            isActive: (row['is_active'] as int) != 0,
          );
        })
        .where((row) {
          if (query.isNotEmpty &&
              !row.name.toLowerCase().contains(query) &&
              row.barcode?.toLowerCase() != query) {
            return false;
          }
          return switch (filter) {
            InventoryFilter.all => true,
            InventoryFilter.lowStock => row.isLowStock,
            InventoryFilter.outOfStock => row.isOutOfStock,
          };
        })
        .toList();
  }

  Future<List<InventoryMovementRow>> history({
    String? productId,
    int limit = 250,
  }) async {
    final movements = db.inventoryMovements;
    // Read-only joins that resolve a movement's document for display.
    final refSale = db.alias(db.sales, 'ref_sale');
    final refReturn = db.alias(db.saleReturns, 'ref_return');
    final refVoid = db.alias(db.saleVoids, 'ref_void');
    final returnSale = db.alias(db.sales, 'return_sale');
    final voidSale = db.alias(db.sales, 'void_sale');
    final refPurchase = db.alias(db.purchases, 'ref_purchase');
    final q =
        db.select(db.inventoryMovements).join([
            innerJoin(
              db.shopProducts,
              db.shopProducts.id.equalsExp(db.inventoryMovements.productId) &
                  db.shopProducts.shopId.equalsExp(
                    db.inventoryMovements.shopId,
                  ),
            ),
            leftOuterJoin(
              db.masterProducts,
              db.masterProducts.id.equalsExp(db.shopProducts.masterProductId),
            ),
            leftOuterJoin(
              refSale,
              movements.referenceType.equals('sale') &
                  refSale.id.equalsExp(movements.referenceId) &
                  refSale.shopId.equalsExp(movements.shopId),
            ),
            leftOuterJoin(
              refReturn,
              movements.referenceType.equals('sale_return') &
                  refReturn.id.equalsExp(movements.referenceId) &
                  refReturn.shopId.equalsExp(movements.shopId),
            ),
            leftOuterJoin(
              returnSale,
              returnSale.id.equalsExp(refReturn.originalSaleId) &
                  returnSale.shopId.equalsExp(movements.shopId),
            ),
            leftOuterJoin(
              refVoid,
              movements.referenceType.equals('sale_void') &
                  refVoid.id.equalsExp(movements.referenceId) &
                  refVoid.shopId.equalsExp(movements.shopId),
            ),
            leftOuterJoin(
              voidSale,
              voidSale.id.equalsExp(refVoid.originalSaleId) &
                  voidSale.shopId.equalsExp(movements.shopId),
            ),
            leftOuterJoin(
              refPurchase,
              movements.referenceType.equals('purchase') &
                  refPurchase.id.equalsExp(movements.referenceId) &
                  refPurchase.shopId.equalsExp(movements.shopId),
            ),
          ])
          ..where(db.inventoryMovements.shopId.equals(shopId))
          ..orderBy([OrderingTerm.desc(db.inventoryMovements.createdAt)])
          ..limit(limit);
    if (productId != null) {
      q.where(db.inventoryMovements.productId.equals(productId));
    }
    return (await q.get()).map((row) {
      final movement = row.readTable(db.inventoryMovements);
      final product = row.readTable(db.shopProducts);
      final master = row.readTableOrNull(db.masterProducts);
      final sale =
          row.readTableOrNull(refSale) ??
          row.readTableOrNull(returnSale) ??
          row.readTableOrNull(voidSale);
      final purchaseInvoice = row
          .readTableOrNull(refPurchase)
          ?.invoiceNumber
          ?.trim();
      return InventoryMovementRow(
        id: movement.id,
        productName: product.customName ?? master?.name ?? 'Unnamed product',
        type: movement.type,
        quantity: movement.quantity,
        note: movement.note,
        createdAt: movement.createdAt,
        referenceType: movement.referenceType,
        reference: sale != null
            ? billReference(sale.id, invoiceNumber: sale.invoiceNumber)
            : purchaseInvoice != null && purchaseInvoice.isNotEmpty
            ? 'Invoice $purchaseInvoice'
            : null,
      );
    }).toList();
  }
}
