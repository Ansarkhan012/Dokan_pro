import 'product_management_models.dart';

/// Comparison key for spotting likely duplicate product names: case, spacing
/// and punctuation are ignored, so `Surf Excel 1kg` and `Surf excel 1 Kg`
/// match. Presentation-time warning only; never stored or enforced.
String normalizeProductName(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9؀-ۿ]+'), '');

final class ProductDuplicate {
  const ProductDuplicate(this.product, {required this.sameBarcode});
  final ManagedProduct product;

  /// True when the barcode matched; otherwise the normalized name did.
  final bool sameBarcode;
}

/// Existing shop products that a new custom product most likely duplicates:
/// the same non-empty barcode, or the same normalized name.
List<ProductDuplicate> findLikelyDuplicates(
  Iterable<ManagedProduct> existing, {
  required String name,
  String? barcode,
}) {
  final key = normalizeProductName(name);
  final code = barcode?.trim() ?? '';
  final matches = <ProductDuplicate>[];
  for (final product in existing) {
    final sameBarcode =
        code.isNotEmpty && (product.barcode?.trim() ?? '') == code;
    final sameName =
        key.isNotEmpty && normalizeProductName(product.name) == key;
    if (sameBarcode || sameName) {
      matches.add(ProductDuplicate(product, sameBarcode: sameBarcode));
    }
  }
  return matches;
}
