import '../../../core/domain/enums.dart';

final class CustomerLedgerAmount {
  const CustomerLedgerAmount(this.type, this.amountMinor);
  final CustomerLedgerType type;
  final int amountMinor;
  int get signedAmount => amountMinor.abs() * type.balanceSign;
}

int calculateCustomerBalance(Iterable<CustomerLedgerAmount> entries) =>
    entries.fold(0, (balance, entry) => balance + entry.signedAmount);
