import '../../core/domain/enums.dart';

final class SupplierAccount {
  const SupplierAccount({
    required this.id,
    required this.name,
    required this.isActive,
    required this.payableMinor,
    required this.totalPurchasesMinor,
    required this.totalPaymentsMinor,
    this.contactPerson,
    this.phone,
    this.address,
    this.notes,
  });
  final String id, name;
  final String? contactPerson, phone, address, notes;
  final bool isActive;
  final int payableMinor, totalPurchasesMinor, totalPaymentsMinor;
}

final class SupplierInput {
  const SupplierInput({
    required this.name,
    this.contactPerson,
    this.phone,
    this.address,
    this.notes,
    this.isActive = true,
  });
  final String name;
  final String? contactPerson, phone, address, notes;
  final bool isActive;
}

final class PurchaseLineDraft {
  const PurchaseLineDraft({
    required this.productId,
    required this.quantity,
    required this.unitCostMinor,
  });
  final String productId;
  final int quantity, unitCostMinor;
}

final class PurchasePaymentDraft {
  const PurchasePaymentDraft({
    required this.method,
    required this.amountMinor,
    this.reference,
  });
  final PaymentMethod method;
  final int amountMinor;
  final String? reference;
}

final class PurchaseDraft {
  const PurchaseDraft({
    required this.shopId,
    required this.supplierId,
    required this.deviceId,
    required this.ownerId,
    required this.lines,
    required this.payments,
    this.invoiceNumber,
    this.notes,
    this.purchaseDate,
  });
  final String shopId, supplierId, deviceId, ownerId;
  final List<PurchaseLineDraft> lines;
  final List<PurchasePaymentDraft> payments;
  final String? invoiceNumber, notes;
  final DateTime? purchaseDate;
}

final class CreatedPurchase {
  const CreatedPurchase({
    required this.purchaseId,
    required this.operationId,
    required this.totalMinor,
    required this.paidMinor,
    required this.dueMinor,
  });
  final String purchaseId, operationId;
  final int totalMinor, paidMinor, dueMinor;
}

final class PurchaseSummary {
  const PurchaseSummary({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.date,
    required this.itemCount,
    required this.totalMinor,
    required this.paidMinor,
    required this.status,
    this.invoiceNumber,
    this.notes,
  });
  final String id, supplierId, supplierName;
  final DateTime date;
  final int itemCount, totalMinor, paidMinor;
  final PaymentStatus status;
  final String? invoiceNumber, notes;
  int get dueMinor => totalMinor - paidMinor;
}

final class PurchaseLineView {
  const PurchaseLineView({
    required this.name,
    required this.quantity,
    required this.unitCostMinor,
    required this.lineTotalMinor,
  });
  final String name;
  final int quantity, unitCostMinor, lineTotalMinor;
}

final class SupplierLedgerLine {
  const SupplierLedgerLine({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.date,
    required this.runningBalanceMinor,
    this.purchaseId,
    this.reference,
    this.note,
  });
  final String id;
  final SupplierLedgerType type;
  final int amountMinor, runningBalanceMinor;
  final DateTime date;
  final String? purchaseId, reference, note;
  int get signedAmountMinor => amountMinor.abs() * type.balanceSign;
}
