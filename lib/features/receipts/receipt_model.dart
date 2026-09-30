enum ReceiptPaperWidth { mm58, mm80 }

final class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });
  final String name;
  final int quantity, unitPrice, total;
}

/// Immutable, transport-neutral receipt snapshot. Historical instances are
/// built only from sale/item snapshots, never from the current product row.
final class ReceiptModel {
  const ReceiptModel({
    required this.shopName,
    required this.reference,
    required this.dateTime,
    required this.cashier,
    required this.lines,
    required this.subtotal,
    required this.total,
    required this.payments,
    this.phone,
    this.address,
    this.customer,
    this.received,
    this.change = 0,
    this.returned = 0,
    this.status = 'Completed',
    this.footer,
  });
  final String shopName, reference, cashier, status;
  final String? phone, address, customer, footer;
  final DateTime dateTime;
  final List<ReceiptLine> lines;
  final int subtotal, total, change, returned;
  final int? received;
  final Map<String, int> payments;
  int get netTotal => total - returned;
}
