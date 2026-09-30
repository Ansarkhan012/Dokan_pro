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
