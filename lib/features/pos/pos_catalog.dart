import 'pos_state.dart';

final class PosCatalogSnapshot {
  const PosCatalogSnapshot({
    required this.products,
    required this.categories,
    required this.customers,
    this.allowNegativeStock = true,
  });

  final List<PosProduct> products;

  /// The shop's stock policy (U2 picker): when false a measured quantity
  /// beyond available stock is refused, as checkout refuses it.
  final bool allowNegativeStock;
  final List<PosCategory> categories;
  final List<PosCustomer> customers;
}

abstract interface class PosCatalog {
  Future<PosCatalogSnapshot> load();
}
