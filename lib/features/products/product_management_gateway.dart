import 'product_management_models.dart';

abstract interface class ProductManagementGateway {
  Future<List<MasterCatalogItem>> searchMasterCatalog({
    required String shopId,
    required String query,
  });

  Future<String> addMasterProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required String masterProductId,
    required AddProductInput input,
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
  });
}
