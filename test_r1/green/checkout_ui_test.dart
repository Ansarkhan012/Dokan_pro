// R1.1 checkout contract at the POS screen: one payment-confirmation attempt
// mints one checkout id and reaches one success state; a failure before the
// local commit keeps the cart; after a restart the last committed sale is
// offered for reprint; a zero-total confirmation carries no payment row.
@Tags(['r1-green'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pos_fixture.dart';

const _catalog = PosCatalogSnapshot(products: [coke], categories: [], customers: []);

final class _CountingIds implements IdGenerator {
  final minted = <String>[];
  @override
  String next() {
    final id = const UuidV7Generator().next();
    minted.add(id);
    return id;
  }
}

Future<void> _pumpPos(
  WidgetTester tester,
  PosHarness h, {
  IdGenerator checkoutIds = const UuidV7Generator(),
  SaleHistoryRow? lastSavedSale,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: PosWorkspace(
      shopName: 'Shop',
      cashierName: 'cashier',
      initialCatalog: _catalog,
      committer: h.committer,
      salesHistory: DriftSalesHistoryRepository(h.db, shopId: shopId),
      offline: false,
      initialHasPendingSync: false,
      onLogout: () async {},
      checkoutIds: checkoutIds,
      lastSavedSale: lastSavedSale,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _disposePos(WidgetTester tester, PosHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  await h.close();
}

void main() {
  testWidgets('E: rapid double taps mint one checkout id and complete one sale (25 rounds)', (tester) async {
    const rounds = 25;
    final h = await PosHarness.open();
    final ids = _CountingIds();
    await _pumpPos(tester, h, checkoutIds: ids);
    for (var round = 1; round <= rounds; round++) {
      await tester.tap(find.text('Add').first);
      await tester.pump();
      // Two taps inside one frame on "Pay", then on "Complete Sale". Odd
      // rounds invoke each button's handler twice directly (both taps reach
      // the code: the worst case); even rounds use two real pointer taps.
      final pay = find.byKey(const ValueKey('pay-button'));
      final completeSale = find.widgetWithText(FilledButton, 'Complete Sale');
      if (round.isOdd) {
        final onPay = tester.widget<FilledButton>(pay).onPressed!;
        onPay();
        onPay();
      } else {
        await tester.tap(pay);
        await tester.tap(pay, warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(completeSale, findsOneWidget, reason: 'one payment dialog');
      if (round.isOdd) {
        final onConfirm = tester.widget<FilledButton>(completeSale).onPressed!;
        onConfirm();
        onConfirm();
      } else {
        await tester.tap(completeSale);
        await tester.tap(completeSale, warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sale completed'), findsOneWidget, reason: 'one success state');
      expect(ids.minted, hasLength(round), reason: 'one checkout id per attempt');
      expect(await h.count('sales'), round);
      final sales = await h.db.select(h.db.sales).get();
      expect(sales.map((s) => s.id).toSet(), ids.minted.toSet());
      await tester.tap(find.text('New sale'));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(await h.count('inventory_movements'), 2 + rounds);
    expect(await h.count('sale_payments'), rounds);
    await _disposePos(tester, h);
  });

  testWidgets('H: a failure before the local commit reports "not saved" and keeps the cart', (tester) async {
    final h = await PosHarness.open();
    await h.db.customStatement(
      "create temp trigger r1_fail_outbox before insert on sync_operations "
      "begin select raise(abort, 'simulated local failure'); end",
    );
    await _pumpPos(tester, h);
    await tester.tap(find.text('Add').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay-button')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Complete Sale'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Nothing was charged'), findsOneWidget);
    expect(find.text('Pay Rs 180.00'), findsOneWidget, reason: 'cart remains for retry');
    expect(find.text('Sale completed'), findsNothing);
    expect(await h.count('sales'), 0);
    expect(h.gateway.calls, 0);
    await _disposePos(tester, h);
  });

  testWidgets('F: after a restart the last committed sale is offered for reprint from local data', (tester) async {
    final h = await PosHarness.open(mode: GatewayMode.fail);
    final sale = await const PosCheckoutController().complete(
      cart: cartOf([coke]),
      payment: cashPlan,
      commit: () => h.committer.complete(const UuidV7Generator().next(), cartOf([coke]), cashPlan),
    );
    await h.runner.idle;
    final history = DriftSalesHistoryRepository(h.db, shopId: shopId);
    final last = await history.lastSaleOnDevice(
      deviceId,
      since: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
    );
    expect(last?.id, sale.saleId);
    await _pumpPos(tester, h, lastSavedSale: last);
    expect(find.textContaining('Last sale saved'), findsOneWidget);
    expect(find.textContaining('Rs 180.00'), findsWidgets);
    await tester.tap(find.text('View / Reprint'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Print / Reprint'), findsOneWidget);
    expect(find.textContaining('Coke'), findsWidgets);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.textContaining('Last sale saved'), findsNothing);
    expect(await h.count('sales'), 1, reason: 'recovery never re-rings the sale');
    await _disposePos(tester, h);
  });

  for (final mode in ['Cash', 'Digital', 'Udhaar', 'Split']) {
    testWidgets('G: zero-total payment confirmation carries no payment row ($mode)', (tester) async {
      PosPaymentPlan? plan;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => plan = await showDialog<PosPaymentPlan>(
              context: context,
              builder: (_) => const PaymentDialog(
                totalMinor: 0,
                customers: [PosCustomer(id: customerId, name: 'Ahmed', balanceMinor: 0)],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text(mode));
      await tester.pump();
      await tester.tap(find.text('Complete Sale'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(plan, isNotNull, reason: 'Rs 0 is a valid confirmation');
      expect(plan!.payments, isEmpty);
      expect(plan!.validate(0), isNull);
      expect(plan!.payments.where((p) => p.method == PaymentMethod.cash), isEmpty);
    });
  }
}
