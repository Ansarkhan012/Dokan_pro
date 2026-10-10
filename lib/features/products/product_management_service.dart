import '../../core/domain/enums.dart';
import '../../core/errors/safe_error_message.dart';
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

  /// U3: creates every pack size of [family] as its own piece product in
  /// the same family, in order, each with its fixed ids. Validates the whole
  /// family first and sends nothing when it is invalid. When a size fails
  /// after others were created, throws [FamilyCreationIncomplete] listing the
  /// created ids; calling again with the same draft finishes the family
  /// without duplicating products or opening stock (the RPC answers
  /// already_exists for an existing id). [existingBarcodes] are the shop's
  /// barcodes already in use (the server enforces this too).
  Future<List<String>> createFamily({
    required String shopId,
    required String deviceId,
    required ProductFamilyDraft family,
    Set<String> existingBarcodes = const {},
  }) async {
    validateFamily(family, existingBarcodes: existingBarcodes);
    final created = <String>[];
    for (final variant in family.variants) {
      try {
        created.add(
          await gateway.createCustomProduct(
            shopId: shopId,
            deviceId: deviceId,
            shopProductId: variant.productId,
            movementId: variant.movementId,
            input: CustomProductInput(
              name: family.name.trim(),
              categoryId: family.categoryId,
              unit: ProductUnit.pack,
              familyId: family.familyId,
              packLabel: variant.packLabel.trim(),
              barcode: variant.barcode?.trim().isEmpty ?? true
                  ? null
                  : variant.barcode!.trim(),
              purchasePriceMinor: variant.purchasePriceMinor,
              salePriceMinor: variant.salePriceMinor,
              openingQuantity: variant.openingQuantity,
              lowStockLevel: variant.lowStockLevel,
            ),
          ),
        );
      } catch (error) {
        throw FamilyCreationIncomplete(
          created: List.unmodifiable(created),
          failedLabel: variant.packLabel.trim(),
          reason: safeUserMessage(error, fallback: 'it could not be saved'),
        );
      }
    }
    return created;
  }

  /// Family rules (U3), checked before anything is sent.
  static void validateFamily(
    ProductFamilyDraft family, {
    Set<String> existingBarcodes = const {},
  }) {
    if (family.name.trim().isEmpty) {
      throw const ProductValidationException('Product family name is required');
    }
    if (family.categoryId.isEmpty) {
      throw const ProductValidationException('Category is required');
    }
    if (family.variants.isEmpty) {
      throw const ProductValidationException('Add at least one pack size');
    }
    final labels = <String>{}, barcodes = <String>{};
    for (final variant in family.variants) {
      final label = variant.packLabel.trim();
      if (label.isEmpty) {
        throw const ProductValidationException('Every pack needs a size label');
      }
      if (!labels.add(label.toLowerCase().replaceAll(RegExp(r'\s+'), ''))) {
        throw ProductValidationException('Pack size $label is listed twice');
      }
      final barcode = variant.barcode?.trim() ?? '';
      if (barcode.isNotEmpty &&
          (!barcodes.add(barcode) || existingBarcodes.contains(barcode))) {
        throw ProductValidationException(
          'Barcode $barcode is already used in this shop',
        );
      }
      if (variant.salePriceMinor <= 0) {
        throw ProductValidationException('Enter a sale price for $label');
      }
      if (variant.purchasePriceMinor < 0) {
        throw const ProductValidationException('Prices cannot be negative');
      }
      if (variant.openingQuantity < 0 ||
          variant.lowStockLevel < 0 ||
          variant.openingQuantity % 1000 != 0 ||
          variant.lowStockLevel % 1000 != 0) {
        throw ProductValidationException(
          'Stock for $label must be whole packs',
        );
      }
    }
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
