import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const product = PosProduct(
    id: 'coke',
    name: 'Coke',
    salePriceMinor: 18000,
    stockQuantity: 10000,
    stockTrackingEnabled: true,
  );

  test('cart adds and removes products', () {
    final cart = PosCart()..add(product);
    expect(cart.lines, hasLength(1));
    expect(cart.subtotalMinor, 18000);
    cart.remove(product.id);
    expect(cart.isEmpty, isTrue);
  });

  test('cart quantity controls use thousandths', () {
    final cart = PosCart()..add(product);
    cart.increment(product.id);
    expect(cart.lines.single.quantity, 2000);
    expect(cart.subtotalMinor, 36000);
    cart.decrement(product.id);
    expect(cart.lines.single.quantity, 1000);
    cart.decrement(product.id);
    expect(cart.isEmpty, isTrue);
  });

  test('cash plan validates tender and calculates exact change', () {
    const plan = PosPaymentPlan(
      payments: [PosPayment(method: PaymentMethod.cash, amountMinor: 18000)],
      cashReceivedMinor: 20000,
    );
    expect(plan.validate(18000), isNull);
    expect(plan.changeDueFor(18000), 2000);
  });

  test('split payment total must equal sale total', () {
    const valid = PosPaymentPlan(
      payments: [
        PosPayment(method: PaymentMethod.cash, amountMinor: 8000),
        PosPayment(method: PaymentMethod.digital, amountMinor: 10000),
      ],
    );
    expect(valid.validate(18000), isNull);
    const invalid = PosPaymentPlan(
      payments: [
        PosPayment(method: PaymentMethod.cash, amountMinor: 7999),
        PosPayment(method: PaymentMethod.digital, amountMinor: 10000),
      ],
    );
    expect(invalid.validate(18000), isNotNull);
  });

  test('Udhaar requires a customer', () {
    const withoutCustomer = PosPaymentPlan(
      payments: [PosPayment(method: PaymentMethod.credit, amountMinor: 18000)],
    );
    expect(withoutCustomer.validate(18000), 'Select a customer for Udhaar.');
    const withCustomer = PosPaymentPlan(
      payments: [PosPayment(method: PaymentMethod.credit, amountMinor: 18000)],
      customerId: 'customer-a',
    );
    expect(withCustomer.validate(18000), isNull);
  });

  test('money input is parsed without floating point', () {
    expect(parseMoneyMinor('5000'), 500000);
    expect(parseMoneyMinor('12.05'), 1205);
    expect(parseMoneyMinor('1.234'), isNull);
  });

  test('successful checkout commit resets cart', () async {
    final cart = PosCart()..add(product);
    var committed = false;
    final result = await const PosCheckoutController().complete(
      cart: cart,
      payment: const PosPaymentPlan(
        payments: [PosPayment(method: PaymentMethod.cash, amountMinor: 18000)],
      ),
      commit: () async {
        committed = true;
        return const CreatedSale(
          saleId: 'sale-a',
          syncOperationId: 'sync-a',
          grandTotalMinor: 18000,
        );
      },
    );
    expect(committed, isTrue);
    expect(result.saleId, 'sale-a');
    expect(cart.isEmpty, isTrue);
  });
}
