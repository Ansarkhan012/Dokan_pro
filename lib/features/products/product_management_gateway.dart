import 'product_management_models.dart';

/// Saves owner edits to an existing product and archives or restores it.
/// The server accepts these from the shop's active owner only (row-level
/// security), whatever the device shows.
abstract interface class ProductEditGateway {
  /// Writes [edit] for [product] in one request, so it is applied whole or
  /// not at all. A pack variant's shared family name and category are
  /// refused (no atomic server update for every size exists yet). Throws a
  /// `ProductValidationException` for a barcode already used in the shop.
  Future<void> saveEdit({
    required String shopId,
    required ManagedProduct product,
    required ProductEdit edit,
  });

  /// Archives (false) or restores (true) a product. Nothing is deleted:
  /// bills, stock history and reports keep referring to it.
  Future<void> setActive({
    required String shopId,
    required String productId,
    required bool isActive,
  });
}

abstract interface class ProductManagementGateway {
  /// Catalog products matching [query] by name, brand or exact barcode; an
  /// empty [query] browses the whole catalog by name, [masterCatalogPageSize]
  /// rows at a time from [offset]. Rows carry the photo's storage key only.
  Future<List<MasterCatalogItem>> searchMasterCatalog({
    required String shopId,
    required String query,
    int offset = 0,
  });

  /// Adds a catalog product to the shop. A [customName] is the shop's own
  /// name for it (the catalog keeps its name); when it cannot be saved after
  /// the product was added, throws [MasterProductRenameFailed].

  Future<String> addMasterProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required String masterProductId,
    required AddProductInput input,
    String? customName,
  });

  Future<String> createCustomProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required CustomProductInput input,
  });

  Future<void> updateProduct({
    required String shopId,
    required String productId,
    required int purchasePriceMinor,
    required int salePriceMinor,
    required int lowStockLevel,
    required bool isActive,
    // U2: measured products only; null leaves the stored value unchanged.
    List<int>? measurePresets,
    bool? allowCustomQuantity,
  });
}
