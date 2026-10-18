import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import 'product_management_gateway.dart';
import 'product_management_models.dart';
import 'product_management_service.dart';

final class SupabaseProductManagementGateway
    implements ProductManagementGateway, ProductEditGateway {
  SupabaseProductManagementGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<MasterCatalogItem>> searchMasterCatalog({
    required String shopId,
    required String query,
    int offset = 0,
  }) async {
    const selection =
        'id,name,brand,barcode,category_id,default_unit,pack_label,'
        'default_image_path,categories(name)';
    if (query.isEmpty) {
      final page = await client
          .from('master_products')
          .select(selection)
          .eq('is_active', true)
          .order('name')
          .order('id')
          .range(offset, offset + masterCatalogPageSize - 1);
      return _withShopIds(shopId, page, sort: false);
    }
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
    return _withShopIds(shopId, merged.values.toList(), sort: true);
  }

  /// Marks the catalog rows this shop already has.
  Future<List<MasterCatalogItem>> _withShopIds(
    String shopId,
    List<Map<String, dynamic>> rows, {
    required bool sort,
  }) async {
    final ids = [for (final row in rows) row['id']! as String];
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
    final result = rows.map((row) {
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
    }).toList();
    if (sort) result.sort((a, b) => a.name.compareTo(b.name));
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
    String? customName,
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
    final productId = result['product_id']! as String;
    if (customName != null) {
      try {
        await client
            .from('shop_products')
            .update({'custom_name': customName})
            .eq('shop_id', shopId)
            .eq('id', productId);
      } catch (_) {
        throw MasterProductRenameFailed(productId);
      }
    }
    return productId;
  }

  @override
  Future<String> createCustomProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required CustomProductInput input,
  }) async {
    if (input.sellMode == SellMode.measured || input.familyId != null) {
      // U2 loose products and U3 pack variants are created by the U1 owner
      // RPC, which writes the product and its one opening-stock movement in
      // one transaction and answers already_exists for a repeated id.
      final created =
          await client.rpc(
                'create_shop_product',
                params: {
                  'p_payload': {
                    'shop_id': shopId,
                    'device_id': deviceId,
                    'product_id': shopProductId,
                    'movement_id': movementId,
                    'name': input.name.trim(),
                    'category_id': input.categoryId,
                    'barcode': input.barcode?.trim(),
                    'unit': input.unit.name,
                    'image_path': input.imagePath?.trim(),
                    'purchase_price': input.purchasePriceMinor,
                    'sale_price': input.salePriceMinor,
                    'opening_quantity': input.openingQuantity,
                    'low_stock_level': input.lowStockLevel,
                    'sell_mode': input.sellMode.name,
                    'measure_presets': input.measurePresets,
                    'allow_custom_quantity': input.allowCustomQuantity,
                    'family_id': input.familyId,
                    'pack_label': input.packLabel?.trim(),
                  },
                },
              )
              as Map<String, dynamic>;
      return created['product_id']! as String;
    }
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
    List<int>? measurePresets,
    bool? allowCustomQuantity,
  }) async {
    // Prices, threshold, activation and (U2) quick quantities only: selling
    // mode, unit and stock are never written by an edit.
    await client
        .from('shop_products')
        .update({
          'purchase_price': purchasePriceMinor,
          'sale_price': salePriceMinor,
          'low_stock_level': lowStockLevel,
          'is_active': isActive,
          'measure_presets': ?measurePresets,
          'allow_custom_quantity': ?allowCustomQuantity,
        })
        .eq('shop_id', shopId)
        .eq('id', productId);
  }

  @override
  Future<void> saveEdit({
    required String shopId,
    required ManagedProduct product,
    required ProductEdit edit,
  }) async {
    // One request per save. A pack family's shared name and category would
    // need one atomic update of every size; no such server operation exists,
    // so they are refused here rather than half-applied.
    if (product.familyId != null &&
        (edit.name != null || edit.categoryId != null)) {
      throw UnsupportedError(
        'A pack family name or category needs an atomic server update.',
      );
    }
    try {
      // Only columns the owner may update (explicit grants); stock and
      // selling mode are never sent.
      await client
          .from('shop_products')
          .update({
            'purchase_price': edit.purchasePriceMinor,
            'sale_price': edit.salePriceMinor,
            'low_stock_level': edit.lowStockLevel,
            'is_active': edit.isActive,
            'measure_presets': ?edit.measurePresets,
            'allow_custom_quantity': ?edit.allowCustomQuantity,
            if (edit.barcodeChanged) 'barcode': edit.barcode,
            if (edit.unit case final unit?) 'unit': unit.name,
            if (edit.packLabelChanged) 'pack_label': edit.packLabel,
            'custom_name': ?edit.name,
            'category_id': ?edit.categoryId,
          })
          .eq('shop_id', shopId)
          .eq('id', product.id);
    } on PostgrestException catch (e) {
      if (e.code == '23505' && edit.barcode != null) {
        throw ProductValidationException(
          'Barcode ${edit.barcode} is already used in this shop',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> setActive({
    required String shopId,
    required String productId,
    required bool isActive,
  }) => client
      .from('shop_products')
      .update({'is_active': isActive})
      .eq('shop_id', shopId)
      .eq('id', productId);
}
