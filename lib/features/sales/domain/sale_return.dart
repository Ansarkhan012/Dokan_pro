import '../../../core/domain/enums.dart';

final class SaleReturnLineDraft {
  const SaleReturnLineDraft({
    required this.originalSaleItemId,
    required this.quantity,
  });
  final String originalSaleItemId;
  final int quantity;
}

final class SaleReturnDraft {
  const SaleReturnDraft({
    required this.shopId,
    required this.originalSaleId,
    required this.ownerId,
    required this.deviceId,
    required this.refundMethod,
    required this.reason,
    required this.lines,
  });
  final String shopId, originalSaleId, ownerId, deviceId, reason;
  final PaymentMethod refundMethod;
  final List<SaleReturnLineDraft> lines;
}

final class CreatedSaleReturn {
  const CreatedSaleReturn({
    required this.returnId,
    required this.operationId,
    required this.refundAmount,
  });
  final String returnId, operationId;
  final int refundAmount;
}

/// Refund for returning [quantity] of a sale item (U1 rule, mirrored by
/// `sync_sale_return` on the server). Integer arithmetic only.
///
/// The refund is the item's cumulative target after this return minus what
/// was already refunded for it, where the target for a cumulative quantity
/// `q` of [sold] is the whole [lineTotal] at `q == sold` and otherwise
/// `(lineTotal * q + sold ~/ 2) ~/ sold`. A first return equals the previous
/// per-return formula; partial returns can never refund more than
/// [lineTotal] in total, and the return that completes the item refunds
/// exactly the remainder.
int saleReturnRefund({
  required int lineTotal,
  required int sold,
  required int priorQuantity,
  required int priorRefund,
  required int quantity,
}) {
  if (sold <= 0 || quantity <= 0 || priorQuantity < 0) {
    throw ArgumentError('Invalid return quantity.');
  }
  final cumulative = priorQuantity + quantity;
  if (cumulative > sold) {
    throw ArgumentError('Return quantity exceeds quantity sold.');
  }
  final target = cumulative == sold
      ? lineTotal
      : (lineTotal * cumulative + sold ~/ 2) ~/ sold;
  final refund = target - priorRefund;
  return refund < 0 ? 0 : refund;
}
