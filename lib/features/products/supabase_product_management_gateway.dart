import 'package:supabase_flutter/supabase_flutter.dart';
import 'product_management_gateway.dart';
import 'product_management_models.dart';

final class SupabaseProductManagementGateway
    implements ProductManagementGateway {
  SupabaseProductManagementGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<MasterCatalogItem>> searchMasterCatalog({
    required String shopId,
    required String query,
  }) async {
    const selection =
        'id,name,brand,barcode,category_id,default_unit,pack_label,'
        'default_image_path,categories(name)';
    final exactBarcode = await client
        .from('master_products')
        .select(selection)
        .eq('is_active', true)
        .eq('barcode', query)
        .limit(20);
    final byName = await client
        .from('master_products')
        .select(selection)
        .eq('is_active', true)
        .ilike('name', '%$query%')
        .limit(50);
    final byBrand = await client
        .from('master_products')
        .select(selection)
        .eq('is_active', true)
        .ilike('brand', '%$query%')
        .limit(50);
    final merged = <String, Map<String, dynamic>>{};
    for (final row in [...exactBarcode, ...byName, ...byBrand]) {
      merged[row['id']! as String] = row;
    }
    final ids = merged.keys.toList();
    final existing = ids.isEmpty
        ? const <Map<String, dynamic>>[]
        : await client
              .from('shop_products')
              .select('id,master_product_id')
              .eq('shop_id', shopId)
              .inFilter('master_product_id', ids);
    final shopIds = {
      for (final row in existing)
        row['master_product_id']! as String: row['id']! as String,
    };
    final result = merged.values.map((row) {
      final id = row['id']! as String;
      final category = row['categories'] as Map<String, dynamic>?;
      return MasterCatalogItem(
        id: id,
        name: row['name']! as String,
        brand: row['brand']! as String,
        barcode: row['barcode']! as String,
        categoryId: row['category_id'] as String?,
        categoryName: category?['name'] as String? ?? 'Uncategorized',
        unit: row['default_unit']! as String,
        packLabel: row['pack_label'] as String?,
        imagePath: row['default_image_path'] as String?,
        alreadyAdded: shopIds.containsKey(id),
        shopProductId: shopIds[id],
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  @override
  Future<String> addMasterProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required String masterProductId,
    required AddProductInput input,
  }) async {
    final result =
        await client.rpc(
              'add_master_product_to_shop',
              params: {
                'p_shop_id': shopId,
                'p_device_id': deviceId,
                'p_shop_product_id': shopProductId,
                'p_master_product_id': masterProductId,
                'p_purchase_price': input.purchasePriceMinor,
                'p_sale_price': input.salePriceMinor,
                'p_opening_quantity': input.openingQuantity,
                'p_low_stock_level': input.lowStockLevel,
                'p_movement_id': movementId,
              },
            )
            as Map<String, dynamic>;
    return result['product_id']! as String;
  }

  @override
  Future<String> createCustomProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required CustomProductInput input,
  }) async {
    final result =
        await client.rpc(
              'create_custom_shop_product',
              params: {
                'p_shop_id': shopId,
                'p_device_id': deviceId,
                'p_shop_product_id': shopProductId,
                'p_name': input.name.trim(),
                'p_category_id': input.categoryId,
                'p_barcode': input.barcode?.trim(),
                'p_unit': input.unit.name,
                'p_pack_label': input.packLabel?.trim(),
                'p_image_path': input.imagePath?.trim(),
                'p_purchase_price': input.purchasePriceMinor,
                'p_sale_price': input.salePriceMinor,
                'p_opening_quantity': input.openingQuantity,
                'p_low_stock_level': input.lowStockLevel,
                'p_movement_id': movementId,
              },
            )
            as Map<String, dynamic>;
    return result['product_id']! as String;
  }

  @override
  Future<void> updateProduct({
    required String shopId,
    required String productId,
    required int purchasePriceMinor,
    required int salePriceMinor,
    required int lowStockLevel,
    required bool isActive,
  }) async {
    await client
        .from('shop_products')
        .update({
          'purchase_price': purchasePriceMinor,
          'sale_price': salePriceMinor,
          'low_stock_level': lowStockLevel,
          'is_active': isActive,
        })
        .eq('shop_id', shopId)
        .eq('id', productId);
  }
}
