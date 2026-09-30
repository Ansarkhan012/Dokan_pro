import '../../../core/domain/enums.dart';

final class SaleLineDraft {
  const SaleLineDraft({
    required this.productId,
    required this.quantity,
    this.discountMinor = 0,
  });
  final String productId;

  /// Thousandths: one whole unit is 1000.
  final int quantity;
  final int discountMinor;
}

final class SalePaymentDraft {
  const SalePaymentDraft({
    required this.method,
    required this.amountMinor,
    this.reference,
  });
  final PaymentMethod method;
  final int amountMinor;
  final String? reference;
}

final class SaleDraft {
  const SaleDraft({
    required this.shopId,
    required this.cashierId,
    required this.deviceId,
    required this.lines,
    required this.payments,
    this.saleId,
    this.customerId,
    this.invoiceNumber,
  });

  /// The checkout attempt id, minted before the local transaction and used
  /// as the sale id. Committing the same id again returns the committed sale
  /// when the content is the same and throws [CheckoutConflict] otherwise.
  /// Null only for callers without an attempt identity (a fresh id is used).
  final String? saleId;
  final String shopId;
  final String cashierId;
  final String deviceId;
  final String? customerId;
  final String? invoiceNumber;
  final List<SaleLineDraft> lines;
  final List<SalePaymentDraft> payments;
}

final class CreatedSale {
  const CreatedSale({
    required this.saleId,
    required this.syncOperationId,
    required this.grandTotalMinor,
  });
  final String saleId;
  final String syncOperationId;
  final int grandTotalMinor;
}

final class SaleValidationException implements Exception {
  const SaleValidationException(this.message);
  final String message;
  @override
  String toString() => 'SaleValidationException: $message';
}

/// The checkout id is already committed with different content. Nothing was
/// written; the committed sale is unchanged.
final class CheckoutConflict implements Exception {
  const CheckoutConflict(this.saleId);
  final String saleId;
  @override
  String toString() =>
      'CheckoutConflict: sale $saleId is already saved with different content';
}
