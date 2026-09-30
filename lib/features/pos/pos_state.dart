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

  int get totalMinor =>
      (product.salePriceMinor * quantity + quantityScale ~/ 2) ~/ quantityScale;

  PosCartLine copyWith({int? quantity}) =>
      PosCartLine(product: product, quantity: quantity ?? this.quantity);
}

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

  void add(PosProduct product) {
    final current = _lines[product.id];
    _lines[product.id] = PosCartLine(
      product: product,
      quantity: (current?.quantity ?? 0) + quantityScale,
    );
  }

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
