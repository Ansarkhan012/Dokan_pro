import 'pos_state.dart';

final class PosCatalogSnapshot {
  const PosCatalogSnapshot({
    required this.products,
    required this.categories,
    required this.customers,
  });

  final List<PosProduct> products;
  final List<PosCategory> categories;
  final List<PosCustomer> customers;
}

abstract interface class PosCatalog {
  Future<PosCatalogSnapshot> load();
}
