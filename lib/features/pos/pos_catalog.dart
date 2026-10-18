import 'pos_state.dart';

final class PosCatalogSnapshot {
  const PosCatalogSnapshot({
    required this.products,
    required this.categories,
    required this.customers,
    this.allowNegativeStock = true,
    this.activeProductCount,
    this.activeCustomerCount,
  });

  final List<PosProduct> products;

  /// The shop's stock policy (U2 picker): when false a measured quantity
  /// beyond available stock is refused, as checkout refuses it.
  final bool allowNegativeStock;
  final List<PosCategory> categories;
  final List<PosCustomer> customers;

  /// All active products / customers of the shop, when known. The POS loads
  /// at most [posProductLimit] / [posCustomerLimit] of them (B-2); the rest
  /// cannot be searched, scanned or picked, and the cashier is told so.
  final int? activeProductCount;
  final int? activeCustomerCount;

  bool get productsTruncated => (activeProductCount ?? 0) > products.length;
  bool get customersTruncated => (activeCustomerCount ?? 0) > customers.length;
}

/// The most products and customers one POS catalog load holds (B-2).
const posProductLimit = 5000;
const posCustomerLimit = 1000;

abstract interface class PosCatalog {
  Future<PosCatalogSnapshot> load();
}
