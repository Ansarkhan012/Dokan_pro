import '../../core/domain/enums.dart';
import '../../core/format/measure_format.dart';
import '../../core/ids/id_generator.dart';
import 'product_management_gateway.dart';
import 'product_management_models.dart';

final class ProductManagementService {
  ProductManagementService(this.gateway, this.ids);
  final ProductManagementGateway gateway;
  final IdGenerator ids;

  Future<List<MasterCatalogItem>> search({
    required String shopId,
    required String query,
  }) {
    final normalized = query.trim();
    if (normalized.isEmpty) return Future.value(const []);
    return gateway.searchMasterCatalog(shopId: shopId, query: normalized);
  }

  Future<String> addMaster({
    required String shopId,
    required String deviceId,
    required MasterCatalogItem product,
    required AddProductInput input,
  }) {
    if (product.alreadyAdded) {
      throw const ProductValidationException(
        'This product is already in your shop',
      );
    }
    _validateMoneyAndStock(input);
    return gateway.addMasterProduct(
      shopId: shopId,
      deviceId: deviceId,
      shopProductId: ids.next(),
      movementId: ids.next(),
      masterProductId: product.id,
      input: input,
    );
  }

  Future<String> createCustom({
    required String shopId,
    required String deviceId,
    required CustomProductInput input,
  }) {
    if (input.name.trim().isEmpty) {
      throw const ProductValidationException('Product name is required');
    }
    if (input.categoryId.isEmpty) {
      throw const ProductValidationException('Category is required');
    }
    _validateMoneyAndStock(input);
    if (input.sellMode == SellMode.measured) _validateMeasured(input);
    return gateway.createCustomProduct(
      shopId: shopId,
      deviceId: deviceId,
      shopProductId: ids.next(),
      movementId: ids.next(),
      input: input,
    );
  }

  /// U2 loose products: weight (kg) or volume (L), and at most eight valid,
  /// distinct quick quantities. The server enforces the same rules.
  void _validateMeasured(CustomProductInput input) {
    if (input.unit != ProductUnit.kg && input.unit != ProductUnit.liter) {
      throw const ProductValidationException(
        'Loose products are sold by weight (kg) or volume (L)',
      );
    }
    final presets = input.measurePresets ?? const <int>[];
    if (presets.length > maxMeasurePresets) {
      throw const ProductValidationException(
        'Use at most $maxMeasurePresets quick quantities',
      );
    }
    if (presets.any((q) => measureQuantityError(q) != null) ||
        presets.toSet().length != presets.length) {
      throw const ProductValidationException('Quick quantities are not valid');
    }
  }

  void _validateMoneyAndStock(AddProductInput input) {
    if (input.purchasePriceMinor < 0 || input.salePriceMinor < 0) {
      throw const ProductValidationException('Prices cannot be negative');
    }
    if (input.openingQuantity < 0 || input.lowStockLevel < 0) {
      throw const ProductValidationException('Stock values cannot be negative');
    }
  }
}

final class ProductValidationException implements Exception {
  const ProductValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
