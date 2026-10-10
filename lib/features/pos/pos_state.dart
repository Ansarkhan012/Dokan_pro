import '../../core/domain/enums.dart';
import '../sales/domain/sale_draft.dart';

const int quantityScale = 1000;

final class PosProduct {
  const PosProduct({
    required this.id,
    required this.name,
    required this.salePriceMinor,
    required this.stockQuantity,
    required this.stockTrackingEnabled,
    this.barcode,
    this.categoryId,
    this.imagePath,
    this.lowStockLevel,
    this.measureUnit,
    this.measurePresets = const [],
    this.allowCustomQuantity = true,
    this.familyId,
    this.familyName,
    this.packLabel,
  });

  final String id;
  final String name;
  final String? barcode;
  final String? categoryId;
  final String? imagePath;
  final int salePriceMinor;
  final int stockQuantity;
  final bool stockTrackingEnabled;
  final int? lowStockLevel;

  /// Set for a measured product (U1); null for a count.
  final MeasureUnit? measureUnit;

  /// Owner quick quantities in thousandths (U2); empty means the defaults.
  final List<int> measurePresets;
  final bool allowCustomQuantity;

  bool get isMeasured => measureUnit != null;

  /// U3: the pack family this variant belongs to; [familyName] is the
  /// family's own name and [packLabel] the size ([name] combines them).
  final String? familyId;
  final String? familyName;
  final String? packLabel;

  bool get isLowStock =>
      stockTrackingEnabled &&
      lowStockLevel != null &&
      stockQuantity <= lowStockLevel!;
}

final class PosCategory {
  const PosCategory({required this.id, required this.name});
  final String id;
  final String name;
}

final class PosCustomer {
  const PosCustomer({
    required this.id,
    required this.name,
    required this.balanceMinor,
    this.creditLimitMinor,
  });
  final String id;
  final String name;
  final int balanceMinor;
  final int? creditLimitMinor;
}

final class PosCartLine {
  const PosCartLine({required this.product, required this.quantity});
  final PosProduct product;
  final int quantity;

  int get totalMinor => lineTotalMinor(product.salePriceMinor, quantity);

  PosCartLine copyWith({int? quantity}) =>
      PosCartLine(product: product, quantity: quantity ?? this.quantity);
}

/// Exact line value in paisa: (price * thousandths + 500) ~/ 1000, the same
/// rounding as checkout, sync validation and reports.
int lineTotalMinor(int unitPriceMinor, int quantity) =>
    (unitPriceMinor * quantity + quantityScale ~/ 2) ~/ quantityScale;

final class PosPayment {
  const PosPayment({required this.method, required this.amountMinor});
  final PaymentMethod method;
  final int amountMinor;
}

final class PosPaymentPlan {
  const PosPaymentPlan({
    required this.payments,
    this.customerId,
    this.cashReceivedMinor,
  });

  final List<PosPayment> payments;
  final String? customerId;
  final int? cashReceivedMinor;

  int get totalMinor => payments.fold(0, (sum, row) => sum + row.amountMinor);

  int changeDueFor(int grandTotalMinor) {
    final received = cashReceivedMinor;
    return received == null || received <= grandTotalMinor
        ? 0
        : received - grandTotalMinor;
  }

  /// Every payment row must be a real tender (> 0); a Rs 0 sale has none.
  String? validate(int grandTotalMinor) {
    if (grandTotalMinor < 0 ||
        (payments.isEmpty && grandTotalMinor != 0) ||
        payments.any((row) => row.amountMinor <= 0)) {
      return 'Enter a valid payment.';
    }
    if (totalMinor != grandTotalMinor) {
      return 'Payment total must equal the sale total.';
    }
    final credit = payments.any(
      (row) => row.method == PaymentMethod.credit && row.amountMinor > 0,
    );
    if (credit && customerId == null) {
      return 'Select a customer for Udhaar.';
    }
    if (cashReceivedMinor != null && cashReceivedMinor! < grandTotalMinor) {
      return 'Cash received is less than the total.';
    }
    return null;
  }
}

final class PosCart {
  final Map<String, PosCartLine> _lines = {};

  List<PosCartLine> get lines => List.unmodifiable(_lines.values);
  bool get isEmpty => _lines.isEmpty;
  int get subtotalMinor =>
      _lines.values.fold(0, (sum, line) => sum + line.totalMinor);

  void add(PosProduct product) => addQuantity(product, quantityScale);

  /// Adds [quantity] thousandths to the product's single line (U2: a measured
  /// product adds its picked quantity; a piece product adds whole units).
  void addQuantity(PosProduct product, int quantity) {
    if (quantity <= 0) return;
    final current = _lines[product.id];
    _lines[product.id] = PosCartLine(
      product: product,
      quantity: (current?.quantity ?? 0) + quantity,
    );
  }

  /// Sets the line to exactly [quantity] thousandths; zero or less removes it.
  void setQuantity(String productId, int quantity) {
    final current = _lines[productId];
    if (current == null) return;
    if (quantity <= 0) {
      _lines.remove(productId);
    } else {
      _lines[productId] = current.copyWith(quantity: quantity);
    }
  }

  /// Thousandths of [productId] already in the cart.
  int quantityOf(String productId) => _lines[productId]?.quantity ?? 0;

  void increment(String productId) {
    final current = _lines[productId];
    if (current != null) {
      _lines[productId] = current.copyWith(
        quantity: current.quantity + quantityScale,
      );
    }
  }

  void decrement(String productId) {
    final current = _lines[productId];
    if (current == null) return;
    if (current.quantity <= quantityScale) {
      _lines.remove(productId);
    } else {
      _lines[productId] = current.copyWith(
        quantity: current.quantity - quantityScale,
      );
    }
  }

  void remove(String productId) => _lines.remove(productId);
  void clear() => _lines.clear();

  List<SaleLineDraft> toSaleLines() => _lines.values
      .map(
        (line) =>
            SaleLineDraft(productId: line.product.id, quantity: line.quantity),
      )
      .toList();
}

final class PosCheckoutController {
  const PosCheckoutController();

  Future<T> complete<T>({
    required PosCart cart,
    required PosPaymentPlan payment,
    required Future<T> Function() commit,
  }) async {
    if (cart.isEmpty) {
      throw const SaleValidationException('Cart must not be empty');
    }
    final error = payment.validate(cart.subtotalMinor);
    if (error != null) throw SaleValidationException(error);
    final result = await commit();
    cart.clear();
    return result;
  }
}

String minorToInput(int minor) {
  final rupees = minor ~/ 100;
  final paisa = minor.abs() % 100;
  return paisa == 0 ? '$rupees' : '$rupees.${paisa.toString().padLeft(2, '0')}';
}

int? parseMoneyMinor(String input) {
  final match = RegExp(r'^\s*(\d+)(?:\.(\d{0,2}))?\s*$').firstMatch(input);
  if (match == null) return null;
  final rupees = int.tryParse(match.group(1)!);
  if (rupees == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return rupees * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

String formatPkr(int minor) {
  final absolute = minor.abs();
  return '${minor < 0 ? '-' : ''}Rs ${absolute ~/ 100}.'
      '${(absolute % 100).toString().padLeft(2, '0')}';
}

/// One card on the sale grid (U3): a single product, or the visible pack
/// sizes of one family. A family with a single visible size is shown as that
/// product, so it adds directly.
final class PosCatalogEntry {
  const PosCatalogEntry.product(PosProduct this.product) : variants = const [];
  const PosCatalogEntry.family(this.variants) : product = null;

  final PosProduct? product;
  final List<PosProduct> variants;

  bool get isFamily => product == null;
  String get name => product?.name ?? variants.first.familyName!;
  int get fromPriceMinor =>
      variants.map((v) => v.salePriceMinor).reduce((a, b) => a < b ? a : b);
}

/// Groups explicitly linked pack variants (same family id) into one entry at
/// the position of the first size; every other product stays its own entry.
/// Products are never grouped by similar names.
List<PosCatalogEntry> groupCatalog(Iterable<PosProduct> products) {
  final families = <String, List<PosProduct>>{};
  final order = <Object>[];
  for (final product in products) {
    final family = product.familyId;
    if (family == null) {
      order.add(product);
    } else {
      final sizes = families.putIfAbsent(family, () {
        order.add(family);
        return [];
      });
      sizes.add(product);
    }
  }
  return [
    for (final item in order)
      if (item is PosProduct)
        PosCatalogEntry.product(item)
      else if (families[item]!.length == 1)
        PosCatalogEntry.product(families[item]!.single)
      else
        PosCatalogEntry.family(
          families[item]!..sort((a, b) => a.salePriceMinor - b.salePriceMinor),
        ),
  ];
}

/// POS search (U3): name contains the query (also ignoring spaces, so
/// `500g` finds `Tapal Danedar 500 g`), or the barcode is exactly it.
bool matchesPosSearch(PosProduct product, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final name = product.name.toLowerCase();
  return name.contains(q) ||
      name.replaceAll(' ', '').contains(q.replaceAll(' ', '')) ||
      product.barcode?.toLowerCase() == q;
}
