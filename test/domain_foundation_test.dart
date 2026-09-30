import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/core/money/money.dart';
import 'package:dukaan_pro/features/customers/domain/customer_balance.dart';
import 'package:dukaan_pro/features/inventory/domain/inventory_calculator.dart';
import 'package:dukaan_pro/features/sales/domain/sale_totals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money arithmetic uses exact minor units', () {
    expect((const Money(1001) + const Money(2002)).minorUnits, 3003);
    expect(const Money(199).multiply(3).minorUnits, 597);
  });

  test('UUID v7 records can be identified offline', () {
    final generator = UuidV7Generator();
    final first = generator.next();
    final second = generator.next();
    expect(first, hasLength(36));
    expect(first, isNot(second));
    expect(first[14], '7');
  });

  test('inventory is reconstructed from signed movements', () {
    final stock = calculateStock(const [
      InventoryDelta(InventoryMovementType.openingStock, 100000),
      InventoryDelta(InventoryMovementType.sale, 12500),
      InventoryDelta(InventoryMovementType.damage, 500),
      InventoryDelta(InventoryMovementType.stockCorrection, -1000),
    ]);
    expect(stock, 86000);
  });

  test('customer balance derives from ledger signs', () {
    final balance = calculateCustomerBalance(const [
      CustomerLedgerAmount(CustomerLedgerType.openingBalance, 100000),
      CustomerLedgerAmount(CustomerLedgerType.creditSale, 300000),
      CustomerLedgerAmount(CustomerLedgerType.paymentReceived, 175000),
    ]);
    expect(balance, 225000);
  });

  test('split cash and credit payments cover sale exactly', () {
    expect(
      paymentsCoverTotal(
        totalMinor: 500000,
        payments: const [SalePaymentAmount(200000), SalePaymentAmount(300000)],
      ),
      isTrue,
    );
    expect(
      paymentsCoverTotal(
        totalMinor: 500000,
        payments: const [SalePaymentAmount(499999)],
      ),
      isFalse,
    );
  });
}
