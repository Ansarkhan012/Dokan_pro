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
  });

  final String id;
  final String name;
  final String categoryName;
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
  bool get isLowStock =>
      lowStockLevel != null && stockQuantity <= lowStockLevel!;
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
  });
  final String name;
  final String categoryId;
  final ProductUnit unit;
  final String? barcode;
  final String? packLabel;
  final String? imagePath;
}

final class ProductCategory {
  const ProductCategory({required this.id, required this.name});
  final String id;
  final String name;
}
