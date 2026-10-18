import 'dart:typed_data';

import '../../core/domain/enums.dart';

enum ProductUnit {
  piece('Piece'),
  pack('Pack'),
  kg('KG'),
  gram('Gram'),
  liter('Liter'),
  bottle('Bottle'),
  carton('Carton'),
  dozen('Dozen'),
  bag('Bag');

  const ProductUnit(this.label);
  final String label;
}

/// Catalog rows fetched per browse page.
const masterCatalogPageSize = 30;

final class MasterCatalogItem {
  const MasterCatalogItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.barcode,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.alreadyAdded,
    this.packLabel,
    this.imagePath,
    this.shopProductId,
  });

  final String id;
  final String name;
  final String brand;
  final String barcode;
  final String? categoryId;
  final String categoryName;
  final String unit;
  final String? packLabel;
  final String? imagePath;
  final bool alreadyAdded;
  final String? shopProductId;
}

final class ManagedProduct {
  const ManagedProduct({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.unit,
    required this.purchasePriceMinor,
    required this.salePriceMinor,
    required this.stockQuantity,
    required this.lowStockLevel,
    required this.isActive,
    required this.isCustom,
    this.barcode,
    this.packLabel,
    this.imagePath,
    this.sellMode = SellMode.piece,
    this.measurePresets,
    this.allowCustomQuantity = true,
    this.familyId,
    this.categoryId,
    this.baseName,
    this.movementCount = 0,
  });

  final String id;

  /// What lists and the POS show: for a pack variant, its family name plus
  /// the pack size.
  final String name;

  /// The stored name (a pack variant's family name, without its size); what
  /// an edit changes. Null means the same as [name].
  final String? baseName;

  /// Stock movements recorded for this product (opening stock, sales,
  /// purchases, adjustments). Its unit is fixed once there are any.
  final int movementCount;
  final String categoryName;

  /// The category's id (null when uncategorized); lets the UI translate a
  /// built-in category by its stable id. Display only.
  final String? categoryId;

  /// U3: the pack family this variant belongs to, if any.
  final String? familyId;
  final String? barcode;
  final String unit;
  final String? packLabel;
  final String? imagePath;
  final int purchasePriceMinor;
  final int salePriceMinor;
  final int stockQuantity;
  final int? lowStockLevel;
  final bool isActive;
  final bool isCustom;

  /// U2: how the product is sold. Fixed at creation.
  final SellMode sellMode;

  /// Owner quick quantities (thousandths); null means the defaults.
  final List<int>? measurePresets;
  final bool allowCustomQuantity;

  /// kg / liter for a measured product, null for a piece product.
  MeasureUnit? get measureUnit =>
      sellMode == SellMode.measured ? MeasureUnit.tryParse(unit) : null;
  bool get isLowStock =>
      lowStockLevel != null && stockQuantity <= lowStockLevel!;

  /// The name an edit starts from.
  String get editableName => baseName ?? name;
}

/// A validated product edit. Identity fields (name, category, barcode, unit,
/// pack label) are set only when changed; null leaves them as stored. Stock
/// and selling mode are never part of an edit: stock changes only through a
/// recorded stock adjustment.
final class ProductEdit {
  const ProductEdit({
    required this.purchasePriceMinor,
    required this.salePriceMinor,
    required this.lowStockLevel,
    required this.isActive,
    this.newImage,
    this.removeImage = false,
    this.measurePresets,
    this.allowCustomQuantity,
    this.name,
    this.categoryId,
    this.barcode,
    this.barcodeChanged = false,
    this.unit,
    this.packLabel,
    this.packLabelChanged = false,
  });
  final int purchasePriceMinor, salePriceMinor, lowStockLevel;
  final bool isActive;

  /// U2, measured products only (null for a piece product): the quick
  /// quantities and custom-quantity switch.
  final List<int>? measurePresets;
  final bool? allowCustomQuantity;
  final Uint8List? newImage;
  final bool removeImage;

  /// New stored name; for a pack variant, the family name shared by every
  /// size.
  final String? name;

  /// New category; for a pack variant, shared by every size.
  final String? categoryId;

  /// New barcode (null clears it) when [barcodeChanged].
  final String? barcode;
  final bool barcodeChanged;

  /// New counting unit; only while the product has no stock history.
  final ProductUnit? unit;

  /// New pack label (null clears it) when [packLabelChanged].
  final String? packLabel;
  final bool packLabelChanged;
}

/// Which products the owner's list shows.
enum ProductListStatus { all, active, archived }

/// Where a product is used. Any history means it can only be archived, never
/// removed, so old bills, stock history and reports keep it.
final class ProductUsage {
  const ProductUsage({
    required this.saleLines,
    required this.purchaseLines,
    required this.returnLines,
    required this.movements,
  });
  final int saleLines, purchaseLines, returnLines, movements;
  bool get hasHistory =>
      saleLines + purchaseLines + returnLines + movements > 0;
}

final class AddProductInput {
  const AddProductInput({
    required this.purchasePriceMinor,
    required this.salePriceMinor,
    required this.openingQuantity,
    required this.lowStockLevel,
  });
  final int purchasePriceMinor;
  final int salePriceMinor;
  final int openingQuantity;
  final int lowStockLevel;
}

final class CustomProductInput extends AddProductInput {
  const CustomProductInput({
    required this.name,
    required this.categoryId,
    required this.unit,
    required super.purchasePriceMinor,
    required super.salePriceMinor,
    required super.openingQuantity,
    required super.lowStockLevel,
    this.barcode,
    this.packLabel,
    this.imagePath,
    this.sellMode = SellMode.piece,
    this.measurePresets,
    this.allowCustomQuantity = true,
    this.familyId,
  });
  final String name;
  final String categoryId;

  /// U3: set for a pack variant; [packLabel] then names the size.
  final String? familyId;

  /// For a measured product: [ProductUnit.kg] (weight) or
  /// [ProductUnit.liter] (volume); prices and stock are per that unit.
  final ProductUnit unit;
  final SellMode sellMode;

  /// Measured quick quantities in thousandths (at most 8); null for none.
  final List<int>? measurePresets;
  final bool allowCustomQuantity;
  final String? barcode;
  final String? packLabel;
  final String? imagePath;
}

final class ProductCategory {
  const ProductCategory({required this.id, required this.name});
  final String id;
  final String name;
}

/// One pack size of a family being created (U3). Its product and opening
/// movement ids are minted once, when the row is added, and kept across
/// retries, so a retry after a partial failure re-sends the same ids and the
/// server answers `already_exists` instead of creating a second product or
/// a second opening movement.
final class PackVariantDraft {
  const PackVariantDraft({
    required this.productId,
    required this.movementId,
    required this.packLabel,
    required this.purchasePriceMinor,
    required this.salePriceMinor,
    required this.openingQuantity,
    required this.lowStockLevel,
    this.barcode,
  });
  final String productId, movementId, packLabel;
  final String? barcode;
  final int purchasePriceMinor, salePriceMinor;

  /// Whole packs in thousandths (1 pack = 1000).
  final int openingQuantity, lowStockLevel;
}

/// A packaged product family (U3): one piece product per pack size, all
/// sharing [familyId], [name] and [categoryId].
final class ProductFamilyDraft {
  const ProductFamilyDraft({
    required this.familyId,
    required this.name,
    required this.categoryId,
    required this.variants,
  });
  final String familyId, name, categoryId;
  final List<PackVariantDraft> variants;
}

/// Some pack sizes were created and one failed (U3). Nothing is rolled back:
/// [created] exist with their opening stock; retrying the same draft creates
/// only the rest.
final class FamilyCreationIncomplete implements Exception {
  const FamilyCreationIncomplete({
    required this.created,
    required this.failedLabel,
    required this.reason,
  });

  /// Product ids that now exist on the server.
  final List<String> created;
  final String failedLabel;
  final String reason;

  @override
  String toString() =>
      'Pack $failedLabel was not created: $reason. '
      '${created.length} size(s) already saved; '
      'press Create again to finish without duplicating them.';
}
