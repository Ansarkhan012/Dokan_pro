import '../../core/domain/enums.dart';

final class CustomerAccount {
  const CustomerAccount({
    required this.id,
    required this.name,
    required this.isActive,
    required this.balanceMinor,
    required this.totalCreditMinor,
    required this.totalPaymentsMinor,
    this.phone,
    this.address,
    this.notes,
    this.creditLimitMinor,
  });

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final int? creditLimitMinor;
  final bool isActive;
  final int balanceMinor;
  final int totalCreditMinor;
  final int totalPaymentsMinor;
}

final class CustomerLedgerLine {
  const CustomerLedgerLine({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.createdAt,
    required this.runningBalanceMinor,
    this.saleId,
    this.paymentReference,
    this.paymentMethod,
    this.note,
  });

  final String id;
  final CustomerLedgerType type;
  final int amountMinor;
  final DateTime createdAt;
  final int runningBalanceMinor;
  final String? saleId;
  final String? paymentReference;
  final String? paymentMethod;
  final String? note;
  int get signedAmountMinor => amountMinor.abs() * type.balanceSign;
}

final class CustomerInput {
  const CustomerInput({
    required this.name,
    this.phone,
    this.address,
    this.notes,
    this.creditLimitMinor,
    this.isActive = true,
  });
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final int? creditLimitMinor;
  final bool isActive;
}
