// F-1 regression tests, moved here from red/f1_checkout_durability_red_test.dart
// by R1.1 with their names and assertions unchanged. In R1.0 they drove a
// copy of the old committer (local commit, then an awaited SyncWorker.runOnce)
// or a stand-in that threw / never returned after its commit; they now drive
// the production committer (DriftPosSaleCommitter) and its background
// SyncWorkerRunner against the same failing and hanging server behaviour.
@Tags(['r1-green'])
library;

import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pos_fixture.dart';

const _catalog = PosCatalogSnapshot(products: [coke], categories: [], customers: []);

Future<void> _pumpPos(WidgetTester tester, PosHarness h) async {
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
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _ringUpAndPay(WidgetTester tester) async {
  await tester.tap(find.text('Add').first);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('pay-button')));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Complete Sale'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Disposes the widget tree (cancels PosWorkspace's periodic retry timer) and
/// lets snack bars, animations and the background sync finish.
Future<void> _disposePos(WidgetTester tester, PosHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  await h.close();
}

void main() {
  test(
    'F-1 data layer: post-commit sync failure escapes, cart is not cleared, retry creates a second sale',
    () async {
      final h = await PosHarness.open(mode: GatewayMode.leaseLost);
      addTearDown(h.db.close);
      final committer = h.committer;
      final cart = PosCart()..add(coke);
      const plan = cashPlan;
      // One payment-confirmation attempt: its checkout id is reused by retries.
      const checkoutId = '0190a000-0000-7000-8000-000000000001';
      Future<Object?> attempt() async {
        try {
          await const PosCheckoutController().complete(
            cart: cart, payment: plan, commit: () => committer.complete(checkoutId, cart, plan),
          );
          return null;
        } catch (e) {
          return e;
        }
      }

      final firstError = await attempt();
      await h.runner.idle; // the background sync ran and failed (lease lost)
      final salesAfterFirst = (await h.db.select(h.db.sales).get()).length;
      final cartClearedAfterFirst = cart.isEmpty;
      final retryError = await attempt();
      await h.runner.idle;
      final sales = await h.db.select(h.db.sales).get();
      // ignore: avoid_print
      print('F1_DATA_EVIDENCE first error=$firstError | sales after first=$salesAfterFirst | '
          'cart cleared=$cartClearedAfterFirst | retry error=$retryError | '
          'sales after retry=${sales.length} | gateway calls=${h.gateway.calls} | '
          'outbox=${(await h.outbox()).map((o) => o.status.name).toList()}');
      expect(h.gateway.calls, greaterThan(0), reason: 'the failing sync really ran');
      expect(salesAfterFirst, 1);
      expect(firstError, isNull, reason: 'a committed sale must be reported as completed');
      expect(sales.length, 1, reason: 'one real checkout must be one financial sale');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'F-1 UI layer (throw): committed sale must not be reported as "Nothing was charged"',
    (tester) async {
      final h = await PosHarness.open(mode: GatewayMode.leaseLost);
      await _pumpPos(tester, h);
      await _ringUpAndPay(tester);
      final nothingCharged = find.textContaining('Nothing was charged').evaluate().isNotEmpty;
      final cartStillPayable = find.text('Pay Rs 180.00').evaluate().isNotEmpty;
      final sales = await h.count('sales');
      // ignore: avoid_print
      print('F1_UI_THROW_EVIDENCE sales=$sales, gateway calls=${h.gateway.calls}, '
          '"Nothing was charged" shown=$nothingCharged, Pay button still armed=$cartStillPayable');
      await _disposePos(tester, h);
      expect(nothingCharged, isFalse);
      expect(cartStillPayable, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'F-1 UI layer (hang): committed sale must show a receipt, not an endless spinner',
    (tester) async {
      final h = await PosHarness.open(mode: GatewayMode.hang);
      await _pumpPos(tester, h);
      await _ringUpAndPay(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      final spinner = find.text('Completing…').evaluate().isNotEmpty;
      final receipt = find.text('View receipt').evaluate().isNotEmpty;
      // ignore: avoid_print
      print('F1_UI_HANG_EVIDENCE after 30s simulated: "Completing…" shown=$spinner, receipt shown=$receipt, '
          'gateway calls=${h.gateway.calls}');
      await _disposePos(tester, h);
      expect(spinner, isFalse);
      expect(receipt, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
