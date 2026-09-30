final class SalePaymentAmount {
  const SalePaymentAmount(this.amountMinor);
  final int amountMinor;
}

int totalPayments(Iterable<SalePaymentAmount> payments) =>
    payments.fold(0, (total, payment) => total + payment.amountMinor);

bool paymentsCoverTotal({
  required int totalMinor,
  required Iterable<SalePaymentAmount> payments,
}) => totalPayments(payments) == totalMinor;
