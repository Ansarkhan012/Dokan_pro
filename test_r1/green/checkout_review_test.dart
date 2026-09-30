// R1.1 review corrections, data layer: the canonical same-id replay
// comparison (every field of the checkout intent, duplicate multiplicity,
// no prices or timestamps), customer payments keeping their pre-R1.1
// "wait for one sync attempt" semantics, and committed sales staying
// discoverable after a restart of any delay.
@Tags(['r1-green'])
library;

import 'dart:io';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pos_fixture.dart';

String _id() => const UuidV7Generator().next();

const _coke = SaleLineDraft(productId: cokeId, quantity: 1000);
const _free = SaleLineDraft(productId: freeId, quantity: 1000);
SalePaymentDraft _cash(int amount, [String? reference]) =>
    SalePaymentDraft(method: PaymentMethod.cash, amountMinor: amount, reference: reference);

SaleDraft _draft(
  String saleId,
  List<SaleLineDraft> lines,
  List<SalePaymentDraft> payments, {
  String cashierId = ownerId,
  String deviceId = deviceId,
  String? customerId,
  String? invoiceNumber,
}) =>
    SaleDraft(
      saleId: saleId,
      shopId: shopId,
      cashierId: cashierId,
      deviceId: deviceId,
      customerId: customerId,
      invoiceNumber: invoiceNumber,
      lines: lines,
      payments: payments,
    );

void main() {
  group('canonical replay comparison audit', () {
    final conflicts = <String, (SaleDraft Function(String), SaleDraft Function(String))>{
      'two lines of 1 vs one line of 2': (
        (id) => _draft(id, [_coke, _coke], [_cash(36000)]),
        (id) => _draft(id, const [SaleLineDraft(productId: cokeId, quantity: 2000)], [_cash(36000)]),
      ),
      'duplicate line dropped': (
        (id) => _draft(id, [_coke, _coke, _free], [_cash(36000)]),
        (id) => _draft(id, [_coke, _free], [_cash(18000)]),
      ),
      'duplicate line added': (
        (id) => _draft(id, [_coke, _free], [_cash(18000)]),
        (id) => _draft(id, [_coke, _free, _free], [_cash(18000)]),
      ),
      'two tenders of 90 vs one of 180': (
        (id) => _draft(id, [_coke], [_cash(9000), _cash(9000)]),
        (id) => _draft(id, [_coke], [_cash(18000)]),
      ),
      'payment reference': (
        (id) => _draft(id, [_coke], [_cash(18000, 'TXN-1')]),
        (id) => _draft(id, [_coke], [_cash(18000, 'TXN-2')]),
      ),
      'payment reference removed': (
        (id) => _draft(id, [_coke], [_cash(18000, 'TXN-1')]),
        (id) => _draft(id, [_coke], [_cash(18000)]),
      ),
      'discount moved between duplicate lines': (
        (id) => _draft(id, const [
              SaleLineDraft(productId: cokeId, quantity: 1000, discountMinor: 1000),
              _coke,
            ], [_cash(35000)]),
        (id) => _draft(id, const [
              SaleLineDraft(productId: cokeId, quantity: 1000, discountMinor: 500),
              SaleLineDraft(productId: cokeId, quantity: 1000, discountMinor: 500),
            ], [_cash(35000)]),
      ),
      'cashier': (
        (id) => _draft(id, [_coke], [_cash(18000)]),
        (id) => _draft(id, [_coke], [_cash(18000)], cashierId: 'someone-else'),
      ),
      'device': (
        (id) => _draft(id, [_coke], [_cash(18000)]),
        (id) => _draft(id, [_coke], [_cash(18000)], deviceId: 'other-device'),
      ),
      'customer added to a cash sale': (
        (id) => _draft(id, [_coke], [_cash(18000)]),
        (id) => _draft(id, [_coke], [_cash(18000)], customerId: customerId),
      ),
      'invoice number removed': (
        (id) => _draft(id, [_coke], [_cash(18000)], invoiceNumber: 'INV-1'),
        (id) => _draft(id, [_coke], [_cash(18000)]),
      ),
    };
    for (final entry in conflicts.entries) {
      test('conflict: ${entry.key}', () async {
        final h = await PosHarness.open();
        addTearDown(h.close);
        final service = LocalSaleService(h.db, const UuidV7Generator());
        final saleId = _id();
        await service.createSale(entry.value.$1(saleId));
        final before = await h.snapshot();
        await expectLater(service.createSale(entry.value.$2(saleId)), throwsA(isA<CheckoutConflict>()));
        expect(await h.snapshot(), before);
      });
    }

    test('same intent with duplicates in another order is the same checkout', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final service = LocalSaleService(h.db, const UuidV7Generator());
      final saleId = _id();
      final first = await service.createSale(
        _draft(saleId, [_coke, _free, _coke], [_cash(9000, 'A'), _cash(27000, 'B')], invoiceNumber: 'INV-7'),
      );
      final before = await h.snapshot();
      final again = await service.createSale(
        _draft(saleId, [_free, _coke, _coke], [_cash(27000, 'B'), _cash(9000, 'A')], invoiceNumber: 'INV-7'),
      );
      expect(again.saleId, first.saleId);
      expect(again.grandTotalMinor, 36000);
      expect(await h.snapshot(), before);
    });

    test('a catalog price change between attempts does not change the checkout', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final service = LocalSaleService(h.db, const UuidV7Generator());
      final saleId = _id();
      await service.createSale(_draft(saleId, [_coke], [_cash(18000)]));
      await h.db.customStatement("update shop_products set sale_price=20000 where id='$cokeId'");
      final before = await h.snapshot();
      // The replay carries the same intent; the committed price snapshot holds.
      final again = await service.createSale(_draft(saleId, [_coke], [_cash(18000)]));
      expect(again.grandTotalMinor, 18000);
      expect(await h.snapshot(), before);
    });

    test('the same id in another shop is a conflict', () async {
      final h = await PosHarness.open();
      addTearDown(h.close);
      final service = LocalSaleService(h.db, const UuidV7Generator());
      final saleId = _id();
      await service.createSale(_draft(saleId, [_coke], [_cash(18000)]));
      final other = SaleDraft(
        saleId: saleId, shopId: 'other-shop', cashierId: ownerId, deviceId: deviceId,
        lines: const [_coke], payments: [_cash(18000)],
      );
      await expectLater(service.createSale(other), throwsA(isA<CheckoutConflict>()));
    });
  });

  group('customer payment keeps waiting for one sync attempt (pre-R1.1 semantics)', () {
    Future<PosHarness> withUdhaar(GatewayMode mode, {Duration? rpcTimeout}) async {
      final h = rpcTimeout == null
          ? await PosHarness.open()
          : await PosHarness.open(rpcTimeout: rpcTimeout);
      await h.committer.complete(_id(), cartOf([coke]), udhaarPlan);
      await h.runner.idle;
      h.gateway.mode = mode;
      return h;
    }

    test('online: the payment is synced when receivePayment returns', () async {
      final h = await withUdhaar(GatewayMode.accept);
      addTearDown(h.close);
      final calls = h.gateway.calls;
      await h.committer.receivePayment(customerId: customerId, amountMinor: 5000, method: PaymentMethod.cash);
      expect(h.gateway.calls, calls + 1);
      expect((await h.outbox()).map((o) => o.status).toSet(), {SyncStatus.synced});
    });

    test('hanging server: returns after the 15 s-class RPC timeout, payment kept and pending', () async {
      const timeout = Duration(milliseconds: 300);
      final h = await withUdhaar(GatewayMode.hang, rpcTimeout: timeout);
      addTearDown(h.close);
      final watch = Stopwatch()..start();
      await h.committer.receivePayment(customerId: customerId, amountMinor: 5000, method: PaymentMethod.cash);
      expect(watch.elapsed, greaterThanOrEqualTo(timeout), reason: 'it waited for the attempt');
      final payment = (await h.outbox()).singleWhere((o) => o.entityType != 'sale_aggregate');
      expect(payment.status, SyncStatus.failed);
      expect(payment.lastError, contains('TimeoutException'));
      expect(await h.count('customer_ledger_entries'), 2);
    });

    test('sync error after the payment commit is not reported as an unsaved payment', () async {
      final h = await withUdhaar(GatewayMode.leaseLost);
      addTearDown(h.close);
      await h.committer.receivePayment(customerId: customerId, amountMinor: 5000, method: PaymentMethod.cash);
      expect(await h.count('customer_ledger_entries'), 2);
    });
  });

  group('committed sales stay discoverable after any restart delay', () {
    test('5 min, 45 min and next morning, sync pending: listed in Bills and reprintable', () async {
      final dir = Directory.systemTemp.createTempSync('r1_1_ages_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}pos.sqlite');
      final now = DateTime.now().toUtc();
      final today = ReportRange.forPreset(ReportRangePreset.today, now);
      final yesterday = ReportRange(
        today.startUtc.subtract(const Duration(days: 1)),
        today.startUtc,
        label: 'Yesterday',
      );
      final ages = {
        '5 minutes': now.subtract(const Duration(minutes: 5)),
        '45 minutes': now.subtract(const Duration(minutes: 45)),
        'next morning': today.startUtc.subtract(const Duration(hours: 2)),
      };
      final h = await PosHarness.open(file: file);
      final ids = <String, String>{};
      for (final entry in ages.entries) {
        ids[entry.key] = (await LocalSaleService(h.db, const UuidV7Generator(), clock: () => entry.value)
                .createSale(_draft(_id(), [_coke], [_cash(18000)])))
            .saleId;
      }
      await h.db.close(); // process ends with every upload still pending

      final r = await PosHarness.open(file: file, seeded: true);
      addTearDown(r.close);
      expect((await r.outbox()).map((o) => o.status).toSet(), {SyncStatus.pending});
      final history = DriftSalesHistoryRepository(r.db, shopId: shopId);
      for (final entry in ages.entries) {
        final range = entry.value.isBefore(today.startUtc) ? yesterday : today;
        final listed = await history.page(filter: SaleHistoryFilter(range: range));
        final row = listed.where((row) => row.id == ids[entry.key]).single;
        expect(row.sync, 'Pending', reason: entry.key);
        final receipt = await history.receipt(await history.detail(row));
        expect(receipt.total, cokePrice, reason: entry.key);
        expect((await history.sale(ids[entry.key]!))?.id, ids[entry.key], reason: entry.key);
      }
      // The banner window is 30 minutes; only the sale inside it is offered.
      final banner = await history.lastSaleOnDevice(deviceId, since: now.subtract(const Duration(minutes: 30)));
      expect(banner?.id, ids['5 minutes']);
    });
  });
}
