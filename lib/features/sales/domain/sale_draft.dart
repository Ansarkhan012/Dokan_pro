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
    this.customerId,
    this.invoiceNumber,
  });
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
