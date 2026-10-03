// R1.1 review corrections at the POS screen: Split at Rs 0, the checkout
// receipt read back from the committed sale, and a committed sale staying
// findable and reprintable in Bills after any restart delay.
@Tags(['r1-green'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/receipts/receipt_model.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:dukaan_pro/features/sales/domain/bill_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pos_fixture.dart';

const _catalog = PosCatalogSnapshot(
  products: [coke, freeBag],
  categories: [],
  customers: [PosCustomer(id: customerId, name: 'Ahmed', balanceMinor: 0)],
);

Future<void> _pumpPos(
  WidgetTester tester,
  PosHarness h, {
  PosSaleCommitter? committer,
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
      committer: committer ?? h.committer,
      salesHistory: DriftSalesHistoryRepository(h.db, shopId: shopId),
      offline: false,
      initialHasPendingSync: false,
      onLogout: () async {},
      lastSavedSale: lastSavedSale,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _addAndOpenPayment(WidgetTester tester, String product) async {
  await tester.tap(find.text(product).first);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('pay-button')));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _disposePos(WidgetTester tester, PosHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  await h.close();
}

/// Everything a receipt states about money, identity and time.
String _authoritative(ReceiptModel r) => [
      r.shopName, r.phone, r.address, r.footer, r.reference,
      r.dateTime.toUtc().toIso8601String(), r.cashier, r.customer, r.status,
      for (final l in r.lines) '${l.name}|${l.quantity}|${l.unitPrice}|${l.total}',
      r.subtotal, r.total, r.returned, r.netTotal,
      (r.payments.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(','),
    ].join(' ; ');

/// Delegates to the production committer; after the commit it makes the
/// sale unreadable, so the receipt read-back fails after the point of no return.
final class _ReceiptReadFails implements PosSaleCommitter {
  _ReceiptReadFails(this.h);
  final PosHarness h;
  @override
  Future<CreatedSale> complete(String id, PosCart cart, PosPaymentPlan p) async {
    final sale = await h.committer.complete(id, cart, p);
    await h.db.customStatement('alter table sale_items rename to sale_items_hidden');
    return sale;
  }

  @override
  Future<PosCatalogSnapshot> reloadCatalog() => h.committer.reloadCatalog();
  @override
  Stream<SyncHealth> watchSyncHealth() => h.committer.watchSyncHealth();
  @override
  Future<bool> triggerSync() => h.committer.triggerSync();
  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) => h.committer.receivePayment(
        customerId: customerId, amountMinor: amountMinor, method: method,
        reference: reference, note: note,
      );
  @override
  Future<List<CustomerAccount>> searchCustomers(String query) => h.committer.searchCustomers(query);
  @override
  Future<List<CustomerLedgerLine>> statement(String id) => h.committer.statement(id);
}

void main() {
  testWidgets('Split at Rs 0: checkout completes with no amount entered and no payment row', (tester) async {
    final h = await PosHarness.open();
    await _pumpPos(tester, h);
    await _addAndOpenPayment(tester, 'Free bag');
    await tester.tap(find.text('Split'));
    await tester.pump();
    await tester.tap(find.text('Complete Sale'));
    await _settle(tester);
    expect(find.text('Sale completed'), findsOneWidget);
    expect(find.textContaining('Enter a valid payment'), findsNothing);
    expect(await h.count('sales'), 1);
    expect(await h.count('sale_payments'), 0);
    expect(await h.stock(freeId), openingStock - 1000);
    await _disposePos(tester, h);
  });

  testWidgets('Split at a positive total: validation is unchanged (empty amounts rejected)', (tester) async {
    final h = await PosHarness.open();
    await _pumpPos(tester, h);
    await _addAndOpenPayment(tester, 'Coke');
    await tester.tap(find.text('Split'));
    await tester.pump();
    await tester.tap(find.text('Complete Sale'));
    await tester.pump();
    expect(find.text('Enter a valid payment.'), findsOneWidget);
    expect(find.text('Complete Sale'), findsOneWidget, reason: 'dialog stays open');
    expect(await h.count('sales'), 0);
    await tester.tap(find.text('Cancel'));
    await _disposePos(tester, h);
  });

  testWidgets('checkout receipt is the committed sale and equals the reopened receipt (Split + Udhaar)', (tester) async {
    final h = await PosHarness.open(mode: GatewayMode.fail);
    await h.db.customStatement(
      "update shops set phone='0300', receipt_show_phone=1, receipt_footer='Thanks'",
    );
    await _pumpPos(tester, h);
    await _addAndOpenPayment(tester, 'Coke');
    await tester.tap(find.text('Split'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Cash amount'), '80');
    await tester.enterText(find.widgetWithText(TextField, 'Digital amount'), '50');
    await tester.enterText(find.widgetWithText(TextField, 'Udhaar amount'), '50');
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Ahmed').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Complete Sale'));
    await _settle(tester);

    final immediate = tester.widget<ReceiptDialog>(find.byType(ReceiptDialog)).receipt;
    expect(immediate, isNotNull);
    final sale = await h.db.select(h.db.sales).getSingle();
    final history = DriftSalesHistoryRepository(h.db, shopId: shopId);
    final reopened = await history.receipt(await history.detail((await history.sale(sale.id))!));
    expect(_authoritative(immediate!), _authoritative(reopened));
    expect(immediate.reference, billReference(sale.id));
    expect(immediate.total, sale.grandTotal);
    expect(immediate.total, cokePrice);
    expect(immediate.payments, {'cash': 8000, 'digital': 5000, 'credit': 5000});
    expect(immediate.customer, 'Ahmed');
    expect(immediate.phone, '0300');
    expect(immediate.footer, 'Thanks');
    expect(immediate.lines.single.unitPrice, cokePrice);
    final ledger = await h.db.select(h.db.customerLedgerEntries).getSingle();
    expect(ledger.amount, 5000);
    await _disposePos(tester, h);
  });

  testWidgets('a receipt that cannot be read back never turns the committed sale into a failure', (tester) async {
    final h = await PosHarness.open();
    await _pumpPos(tester, h, committer: _ReceiptReadFails(h));
    await _addAndOpenPayment(tester, 'Coke');
    await tester.tap(find.text('Complete Sale'));
    await _settle(tester);
    expect(find.text('Sale completed'), findsOneWidget);
    expect(find.text('The sale is saved. Open its receipt from Bills.'), findsOneWidget);
    expect(find.textContaining('Nothing was charged'), findsNothing);
    expect(find.text('Pay Rs 180.00'), findsNothing, reason: 'cart cleared');
    await h.db.customStatement('alter table sale_items_hidden rename to sale_items');
    expect(await h.count('sales'), 1);
    expect(await h.count('sale_items'), 1);
    await _disposePos(tester, h);
  });

  for (final (label, age) in const [
    ('5 minutes', Duration(minutes: 5)),
    ('45 minutes', Duration(minutes: 45)),
    ('the next morning', null),
  ]) {
    testWidgets('restart after $label with sync pending: sale is found in Bills and reprinted', (tester) async {
      final h = await PosHarness.open();
      final now = DateTime.now().toUtc();
      final todayStart = ReportRange.forPreset(ReportRangePreset.today, now).startUtc;
      // "Next morning": sold at 22:00 the previous shop day.
      final soldAt = age == null ? todayStart.subtract(const Duration(hours: 2)) : now.subtract(age);
      final sale = await LocalSaleService(h.db, const UuidV7Generator(),
              clock: () => soldAt, authorizer: const AllowFinancialMutations())
          .createSale(SaleDraft(
        saleId: const UuidV7Generator().next(),
        shopId: shopId,
        cashierId: ownerId,
        deviceId: deviceId,
        lines: const [SaleLineDraft(productId: cokeId, quantity: 1000)],
        payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: cokePrice)],
      ));
      expect((await h.outbox()).single.status, SyncStatus.pending);
      final history = DriftSalesHistoryRepository(h.db, shopId: shopId);
      // What PosRuntime computes at start: the banner covers 30 minutes only.
      final banner = await history.lastSaleOnDevice(deviceId, since: now.subtract(const Duration(minutes: 30)));
      await _pumpPos(tester, h, lastSavedSale: banner);
      expect(find.textContaining('Last sale saved').evaluate().isNotEmpty, age == const Duration(minutes: 5));

      await tester.tap(find.text('Bills'));
      await _settle(tester);
      if (!soldAt.isBefore(todayStart)) {
        expect(find.text('Today'), findsOneWidget);
      } else {
        await tester.tap(find.text('Yesterday'));
        await _settle(tester);
      }
      final tile = find.text('${billReference(sale.saleId)} • Rs 180.00');
      expect(tile, findsOneWidget, reason: 'the committed sale is listed');
      expect(find.text('Pending'), findsWidgets);
      await tester.tap(tile);
      await _settle(tester);
      // The sale dialog's button (the banner may show one too).
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('View / Reprint')));
      await _settle(tester);
      expect(find.text('Receipt'), findsOneWidget);
      expect(find.text('Print / Reprint'), findsOneWidget);
      expect(await h.count('sales'), 1);
      await _disposePos(tester, h);
    });
  }
}
