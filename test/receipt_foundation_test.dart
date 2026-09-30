import 'package:dukaan_pro/features/receipts/receipt_model.dart';
import 'package:dukaan_pro/features/receipts/receipt_printer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final receipt = ReceiptModel(
    shopName: 'Dukaan',
    reference: 'SALE-1',
    dateTime: DateTime.utc(2026, 9, 20),
    cashier: 'Ali',
    customer: 'Ahmed',
    lines: [
      ReceiptLine(
        name: 'Snapshot Tea',
        quantity: 1000,
        unitPrice: 10000,
        total: 10000,
      ),
    ],
    subtotal: 10000,
    total: 10000,
    returned: 4000,
    payments: {'cash': 10000},
    received: 12000,
    change: 2000,
    footer: 'Thank you',
  );

  test('shared receipt preserves snapshots and derives return-aware net', () {
    expect(receipt.lines.single.name, 'Snapshot Tea');
    expect(receipt.netTotal, 6000);
    expect(receipt.change, 2000);
  });

  test(
    'unavailable printer is retryable and never reports a false print',
    () async {
      final result = await const UnavailableReceiptPrinter().print(
        receipt,
        paperWidth: ReceiptPaperWidth.mm58,
      );
      expect(result.printed, isFalse);
      expect(result.message, contains('retry'));
    },
  );
}
