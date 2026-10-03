// R1.1 checkout contract (docs/recovery/r1-stage-a-design.md §B, §J, D1):
// the checkout succeeds exactly when its one local Drift transaction commits;
// nothing after that point (sync failure, hang, process death) changes the
// result, and one payment-confirmation attempt is at most one financial sale.
// Pure local: production committer + background runner, scripted gateway.
@Tags(['r1-green'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sync_worker_runner.dart';
import 'package:dukaan_pro/features/sales/domain/bill_reference.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pos_fixture.dart';

String _id() => const UuidV7Generator().next();

/// Runs [body] and returns every error that escaped to the zone (unhandled).
Future<List<Object>> _uncaught(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    await body();
    done.complete();
  }, (error, _) {
    errors.add(error);
    if (!done.isCompleted) done.completeError(error);
  });
  await done.future;
  return errors;
}

Future<CreatedSale> _checkout(
  PosHarness h,
  String checkoutId,
  PosCart cart,
  PosPaymentPlan plan,
) =>
    const PosCheckoutController().complete(
      cart: cart,
      payment: plan,
      commit: () => h.committer.complete(checkoutId, cart, plan),
    );

Future<void> _expectRetryable(PosHarness h, String saleId) async {
  final op = (await h.outbox()).singleWhere((o) => o.entityId == saleId);
  expect(op.status, isNot(SyncStatus.synced));
  final eligible = await SyncQueueRepository(h.db, shopId: shopId).acquireLease(
    workerId: 'probe',
    now: DateTime.now().toUtc().add(const Duration(minutes: 10)),
  );
  expect(eligible?.id, op.id, reason: 'the queued sale stays retryable');
}

void main() {
  group('A: commit, then the background sync fails', () {
    for (final mode in [GatewayMode.fail, GatewayMode.throwSync, GatewayMode.leaseLost]) {
      test('checkout succeeds once and stays successful (${mode.name})', () async {
        final h = await PosHarness.open(mode: mode);
        addTearDown(h.close);
        final checkoutId = _id();
        final cart = cartOf([coke]);
        late CreatedSale sale;
        final escaped = await _uncaught(() async {
          sale = await _checkout(h, checkoutId, cart, cashPlan);
          await h.runner.idle;
        });
        expect(escaped, isEmpty, reason: 'no sync error may escape unhandled');
        expect(h.gateway.calls, greaterThan(0), reason: 'the sync really ran and failed');
        expect(sale.saleId, checkoutId);
        expect(cart.isEmpty, isTrue);
        expect(await h.count('sales'), 1);

        final history = DriftSalesHistoryRepository(h.db, shopId: shopId);
        final row = await history.lastSaleOnDevice(
          deviceId,
          since: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
        );
        expect(row?.id, sale.saleId);
        final receipt = await history.receipt(await history.detail(row!));
        expect(receipt.total, cokePrice);
        expect(receipt.lines.single.name, 'Coke');
        await _expectRetryable(h, sale.saleId);

        // The same attempt cannot produce a second sale.
        final again = await h.committer.complete(checkoutId, cartOf([coke]), cashPlan);
        await h.runner.idle;
        expect(again.saleId, sale.saleId);
        expect(await h.count('sales'), 1);
      });
    }
  });

  group('B: commit, then the background sync hangs', () {
    test('checkout returns without waiting; the timeout only leaves the sale pending', () async {
      const rpcTimeout = Duration(milliseconds: 400);
      final h = await PosHarness.open(mode: GatewayMode.hang, rpcTimeout: rpcTimeout);
      addTearDown(h.close);
      final cart = cartOf([coke]);
      var runnerIdle = false;
      final watch = Stopwatch()..start();
      final sale = await _checkout(h, _id(), cart, cashPlan);
      watch.stop();
      unawaited(h.runner.idle.then((_) => runnerIdle = true));
      await pumpEventQueue();
      expect(runnerIdle, isFalse, reason: 'sync is still hanging after checkout returned');
      expect(watch.elapsed, lessThan(rpcTimeout));
      expect(cart.isEmpty, isTrue);
      expect(await h.count('sales'), 1);
      expect((await h.outbox()).single.entityId, sale.saleId);

      await h.runner.idle;
      final op = (await h.outbox()).single;
      expect(op.status, SyncStatus.failed);
      expect(op.lastError, contains('TimeoutException'));
      expect(await h.count('sales'), 1);
      await _expectRetryable(h, sale.saleId);
    });

    test('the approved network/RPC timeout is 15 seconds', () {
      expect(SyncWorkerRunner.defaultRpcTimeout, const Duration(seconds: 15));
    });

    testWidgets('a hanging RPC is cut at exactly 15 seconds inside the sync path', (tester) async {
      final hanging = ScriptedGateway(null, GatewayMode.hang);
      Object? outcome;
      unawaited(
        TimeBoundSaleUploadGateway(hanging, SyncWorkerRunner.defaultRpcTimeout)
            .uploadSaleAggregate(const {})
            .then((_) => outcome = 'completed', onError: (Object e) => outcome = e),
      );
      await tester.pump(const Duration(milliseconds: 14999));
      expect(outcome, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(outcome, isA<TimeoutException>());
    });
  });

  group('C: same checkout id + same content', () {
    test('returns the committed sale and writes nothing more (Udhaar, ledger)', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final checkoutId = _id();
      final first = await _checkout(h, checkoutId, cartOf([coke]), udhaarPlan);
      await h.runner.idle;
      final before = await h.snapshot();
      final footprint = await h.footprint();
      final second = await _checkout(h, checkoutId, cartOf([coke]), udhaarPlan);
      await h.runner.idle;
      expect(second.saleId, first.saleId);
      expect(second.syncOperationId, first.syncOperationId);
      expect(second.grandTotalMinor, first.grandTotalMinor);
      expect(await h.snapshot(), before);
      expect(footprint, {
        'sales': 1,
        'sale_items': 1,
        'sale_payments': 1,
        'inventory_movements': 3, // two opening rows + one sale row
        'customer_ledger_entries': 1,
        'audit_logs': 1,
        'sync_operations': 1,
      });
      expect(await h.stock(cokeId), openingStock - 1000);
    });

    test('line and payment order do not matter (canonical comparison)', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final service = LocalSaleService(h.db, const UuidV7Generator());
      final saleId = _id();
      SaleDraft draft(List<SaleLineDraft> lines, List<SalePaymentDraft> payments) => SaleDraft(
            saleId: saleId,
            shopId: shopId,
            cashierId: ownerId,
            deviceId: deviceId,
            lines: lines,
            payments: payments,
          );
      const cokeLine = SaleLineDraft(productId: cokeId, quantity: 2000, discountMinor: 500);
      const freeLine = SaleLineDraft(productId: freeId, quantity: 1000);
      const cash = SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 20000);
      const digital = SalePaymentDraft(method: PaymentMethod.digital, amountMinor: 15500);
      final first = await service.createSale(draft([cokeLine, freeLine], [cash, digital]));
      final before = await h.snapshot();
      final second = await service.createSale(draft([freeLine, cokeLine], [digital, cash]));
      expect(second.saleId, first.saleId);
      expect(await h.snapshot(), before);
    });
  });

  group('D: same checkout id + different content', () {
    const base = SaleDraft(
      shopId: shopId,
      cashierId: ownerId,
      deviceId: deviceId,
      lines: [SaleLineDraft(productId: cokeId, quantity: 1000)],
      payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: cokePrice)],
    );
    SaleDraft variant(
      String saleId, {
      List<SaleLineDraft>? lines,
      List<SalePaymentDraft>? payments,
      String? customerId,
      String? invoiceNumber,
    }) =>
        SaleDraft(
          saleId: saleId,
          shopId: base.shopId,
          cashierId: base.cashierId,
          deviceId: base.deviceId,
          customerId: customerId,
          invoiceNumber: invoiceNumber,
          lines: lines ?? base.lines,
          payments: payments ?? base.payments,
        );
    final variants = <String, SaleDraft Function(String)>{
      'quantity': (id) => variant(id,
          lines: const [SaleLineDraft(productId: cokeId, quantity: 2000)],
          payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 36000)]),
      'product': (id) => variant(id,
          lines: const [SaleLineDraft(productId: freeId, quantity: 1000)], payments: const []),
      'extra line': (id) => variant(id, lines: const [
            SaleLineDraft(productId: cokeId, quantity: 1000),
            SaleLineDraft(productId: freeId, quantity: 1000),
          ]),
      'discount': (id) => variant(id,
          lines: const [SaleLineDraft(productId: cokeId, quantity: 1000, discountMinor: 1000)],
          payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 17000)]),
      'payment method': (id) => variant(id,
          payments: const [SalePaymentDraft(method: PaymentMethod.digital, amountMinor: cokePrice)]),
      'payment split': (id) => variant(id, payments: const [
            SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 8000),
            SalePaymentDraft(method: PaymentMethod.digital, amountMinor: 10000),
          ]),
      'Udhaar customer': (id) => variant(id,
          customerId: customerId,
          payments: const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: cokePrice)]),
      'invoice number': (id) => variant(id, invoiceNumber: 'INV-2'),
    };
    for (final entry in variants.entries) {
      test('different ${entry.key} → CheckoutConflict, nothing written', () async {
        final h = await PosHarness.open();
        addTearDown(h.close);
        final service = LocalSaleService(h.db, const UuidV7Generator());
        final saleId = _id();
        await service.createSale(variant(saleId));
        final before = await h.snapshot();
        await expectLater(
          service.createSale(entry.value(saleId)),
          throwsA(isA<CheckoutConflict>().having((e) => e.saleId, 'saleId', saleId)),
        );
        expect(await h.snapshot(), before);
      });
    }

    test('through the POS committer: cash attempt replayed as Udhaar conflicts', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final checkoutId = _id();
      await _checkout(h, checkoutId, cartOf([coke]), cashPlan);
      await h.runner.idle;
      final before = await h.snapshot();
      final cart = cartOf([coke]);
      await expectLater(
        _checkout(h, checkoutId, cart, udhaarPlan),
        throwsA(isA<CheckoutConflict>()),
      );
      await h.runner.idle;
      expect(cart.isEmpty, isFalse, reason: 'a rejected checkout leaves the cart');
      expect(await h.snapshot(), before);
    });
  });

  group('E: rapid double tap (concurrent invocations of one attempt)', () {
    const rounds = 250;
    test('one committer: $rounds concurrent pairs → exactly one sale each', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      for (var i = 1; i <= rounds; i++) {
        final checkoutId = _id();
        final cartA = cartOf([coke]), cartB = cartOf([coke]);
        // Vary the interleaving: same microtask, next microtask, next event.
        Future<CreatedSale> second() => switch (i % 3) {
              0 => _checkout(h, checkoutId, cartB, cashPlan),
              1 => Future.microtask(() => _checkout(h, checkoutId, cartB, cashPlan)),
              _ => Future(() => _checkout(h, checkoutId, cartB, cashPlan)),
            };
        final results = await Future.wait([_checkout(h, checkoutId, cartA, cashPlan), second()]);
        expect(results.map((r) => r.saleId).toSet(), {checkoutId});
        expect(await h.count('sales'), i);
      }
      await h.runner.idle;
      expect(await h.footprint(), {
        'sales': rounds,
        'sale_items': rounds,
        'sale_payments': rounds,
        'inventory_movements': 2 + rounds,
        'customer_ledger_entries': 0,
        'audit_logs': rounds,
        'sync_operations': rounds,
      });
    });

    test('two committers on one database (no shared in-flight map): still one sale', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final other = PosHarness.attach(h.db);
      for (var i = 1; i <= 100; i++) {
        final checkoutId = _id();
        final results = await Future.wait([
          _checkout(h, checkoutId, cartOf([coke]), udhaarPlan),
          _checkout(other, checkoutId, cartOf([coke]), udhaarPlan),
        ]);
        expect(results.map((r) => r.saleId).toSet(), {checkoutId});
      }
      await h.runner.idle;
      await other.runner.idle;
      expect(await h.count('sales'), 100);
      expect(await h.count('customer_ledger_entries'), 100);
      expect(await h.count('inventory_movements'), 102);
    });
  });

  group('F: process death after commit', () {
    test('the committed sale, its receipt and its queued sync survive a restart', () async {
      final dir = Directory.systemTemp.createTempSync('r1_1_restart_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}pos.sqlite');
      final h = await PosHarness.open(file: file, mode: GatewayMode.hang);
      final cart = cartOf([coke]);
      final sale = await _checkout(h, _id(), cart, cashPlan);
      // The process dies before sync or any further UI work finishes.
      await h.db.close();

      final r = await PosHarness.open(file: file, seeded: true);
      addTearDown(r.close);
      expect(await r.footprint(), {
        'sales': 1,
        'sale_items': 1,
        'sale_payments': 1,
        'inventory_movements': 3,
        'customer_ledger_entries': 0,
        'audit_logs': 1,
        'sync_operations': 1,
      });
      final history = DriftSalesHistoryRepository(r.db, shopId: shopId);
      final last = await history.lastSaleOnDevice(
        deviceId,
        since: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
      );
      expect(last?.id, sale.saleId, reason: 'the app can identify the last committed checkout');
      expect(last!.total, cokePrice);
      final receipt = await history.receipt(await history.detail(last));
      expect(receipt.reference, billReference(sale.saleId));
      expect(receipt.lines.single.name, 'Coke');
      expect(receipt.payments, {'cash': cokePrice});
      expect(receipt.total, cokePrice);
      await _expectRetryable(r, sale.saleId);
      expect(
        await history.lastSaleOnDevice('another-device', since: DateTime.utc(2000)),
        isNull,
      );
    });
  });

  group('G: zero-total sale', () {
    test('commits with zero payment rows, normal stock, audit and outbox', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      const plan = PosPaymentPlan(payments: []);
      final cart = cartOf([freeBag]);
      final checkoutId = _id();
      final sale = await _checkout(h, checkoutId, cart, plan);
      await h.runner.idle;
      expect(cart.isEmpty, isTrue);
      expect(sale.grandTotalMinor, 0);
      expect(await h.footprint(), {
        'sales': 1,
        'sale_items': 1,
        'sale_payments': 0,
        'inventory_movements': 3,
        'customer_ledger_entries': 0,
        'audit_logs': 1,
        'sync_operations': 1,
      });
      expect(await h.stock(freeId), openingStock - 1000);
      final stored = await (h.db.select(h.db.sales)..where((t) => t.id.equals(checkoutId))).getSingle();
      expect(stored.grandTotal, 0);
      final audit = await h.db.select(h.db.auditLogs).getSingle();
      expect(jsonDecode(audit.newValue!), {'grand_total': 0});
      final payload = jsonDecode((await h.outbox()).single.payload) as Map<String, dynamic>;
      expect(payload['payments'], isEmpty);
      expect((payload['sale'] as Map)['grandTotal'], 0);
      expect(payload['inventory_movements'], hasLength(1));
      expect(payload['customer_ledger_entries'], isEmpty);

      final replay = await _checkout(h, checkoutId, cartOf([freeBag]), plan);
      expect(replay.saleId, sale.saleId);
      expect(await h.count('sales'), 1);
    });

    test('payment plan: empty only at total 0; every row must be > 0', () {
      const empty = PosPaymentPlan(payments: []);
      expect(empty.validate(0), isNull);
      expect(empty.validate(cokePrice), isNotNull);
      expect(empty.validate(-1), isNotNull);
      for (final amount in [0, -100]) {
        expect(
          PosPaymentPlan(payments: [PosPayment(method: PaymentMethod.cash, amountMinor: amount)])
              .validate(0),
          isNotNull,
          reason: 'Rs ${amount / 100} row at total 0',
        );
        expect(
          PosPaymentPlan(payments: [
            const PosPayment(method: PaymentMethod.cash, amountMinor: cokePrice),
            PosPayment(method: PaymentMethod.digital, amountMinor: amount),
          ]).validate(cokePrice),
          isNotNull,
          reason: 'Rs ${amount / 100} row inside a positive sale',
        );
      }
    });

    test('LocalSaleService rejects any payment row <= 0 and writes nothing', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final service = LocalSaleService(h.db, const UuidV7Generator());
      final before = await h.snapshot();
      final invalid = <String, (String, List<SalePaymentDraft>)>{
        'Rs 0 cash row on a zero total': (freeId, const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 0)]),
        'Rs 0 digital row on a zero total': (freeId, const [SalePaymentDraft(method: PaymentMethod.digital, amountMinor: 0)]),
        'Rs 0 Udhaar row on a zero total': (freeId, const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 0)]),
        'negative row on a zero total': (freeId, const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: -100)]),
        'Rs 0 row inside a positive sale': (cokeId, const [
          SalePaymentDraft(method: PaymentMethod.cash, amountMinor: cokePrice),
          SalePaymentDraft(method: PaymentMethod.digital, amountMinor: 0),
        ]),
        'no payment on a positive sale': (cokeId, const []),
      };
      for (final entry in invalid.entries) {
        await expectLater(
          service.createSale(SaleDraft(
            saleId: _id(),
            shopId: shopId,
            cashierId: ownerId,
            deviceId: deviceId,
            customerId: customerId,
            lines: [SaleLineDraft(productId: entry.value.$1, quantity: 1000)],
            payments: entry.value.$2,
          )),
          throwsA(isA<SaleValidationException>()),
          reason: entry.key,
        );
      }
      expect(await h.snapshot(), before);
    });
  });

  group('H: failure before the local commit', () {
    test('nothing is written, the cart remains, no sync is woken', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      // The outbox insert is the last statement of the transaction: failing
      // it proves every earlier write of the same checkout is rolled back.
      await h.db.customStatement(
        "create temp trigger r1_fail_outbox before insert on sync_operations "
        "begin select raise(abort, 'simulated local failure'); end",
      );
      final before = await h.snapshot();
      final cart = cartOf([coke]);
      await expectLater(_checkout(h, _id(), cart, udhaarPlan), throwsA(anything));
      await h.runner.idle;
      expect(await h.snapshot(), before);
      expect(await h.count('sales'), 0);
      expect(cart.isEmpty, isFalse);
      expect(cart.subtotalMinor, cokePrice);
      expect(h.gateway.calls, 0);

      // The same cart can be retried once the fault is gone.
      await h.db.customStatement('drop trigger r1_fail_outbox');
      final sale = await _checkout(h, _id(), cart, udhaarPlan);
      expect(cart.isEmpty, isTrue);
      expect(await h.count('sales'), 1);
      expect(await h.count('customer_ledger_entries'), 1);
      await h.runner.idle;
      expect((await h.outbox()).single.entityId, sale.saleId);
    });

    test('validation failure before commit (credit limit) writes nothing', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      await h.db.customStatement("update customers set credit_limit=100 where id='$customerId'");
      final before = await h.snapshot();
      final cart = cartOf([coke]);
      await expectLater(_checkout(h, _id(), cart, udhaarPlan), throwsA(isA<SaleValidationException>()));
      expect(await h.snapshot(), before);
      expect(cart.isEmpty, isFalse);
    });
  });

}
