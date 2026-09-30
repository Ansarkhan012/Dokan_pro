import 'package:drift/drift.dart';
import '../app_database.dart';

final class ShopProductRepository {
  ShopProductRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  Future<List<ShopProduct>> getActive() => (db.select(
    db.shopProducts,
  )..where((t) => t.shopId.equals(shopId) & t.isActive.equals(true))).get();

  Future<ShopProduct?> findByBarcode(String barcode) =>
      (db.select(db.shopProducts)
            ..where((t) => t.shopId.equals(shopId) & t.barcode.equals(barcode)))
          .getSingleOrNull();

  Future<void> save(ShopProductsCompanion product) async {
    if (!product.shopId.present || product.shopId.value != shopId) {
      throw StateError('Cross-shop product write rejected');
    }
    await db.into(db.shopProducts).insertOnConflictUpdate(product);
  }
}
