// R1 Stage A reproduction of audit findings F-3 / O-4: offline-committed
// facts that the server rejects permanently are retried forever with no
// terminal state. Asserts the CORRECT invariant, so it FAILS today.
@Tags(['r1-repro'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Drives the real worker for [attempts] retries, jumping the clock past each
/// backoff window, and reports what happened to the single queued operation.
Future<String> _retryForever(
  AppDatabase db,
  ShopFixture f,
  int attempts,
) async {
  var clock = DateTime.now().toUtc();
  final queue = SyncQueueRepository(db, shopId: f.shopId);
  for (var i = 0; i < attempts; i++) {
    await SyncWorker(
      queue: queue,
      gateway: PsqlUploadGateway(f.ownerId),
      workerId: 'device',
      clock: () => clock,
    ).runOnce();
    clock = clock.add(const Duration(minutes: 6)); // past max 5-min backoff
  }
  final ops = await db.select(db.syncOperations).get();
  final stillEligible = await queue.acquireLease(
    workerId: 'probe',
    now: clock.add(const Duration(days: 30)),
  );
  final rows = ops
      .map(
        (o) =>
            '${o.entityType} status=${o.status.name} retries=${o.retryCount} error="${o.lastError}"',
      )
      .join('; ');
  return '$rows | eligible for automatic retry after 30 days: ${stillEligible != null}';
}

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer();
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });

  test(
    'F-3 zero-amount payment: locally committed sale reaches a terminal state instead of retrying forever',
    () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      // Exactly what PosWorkspace cash mode builds for a Rs 0 total:
      // PosPayment(cash, amountMinor: total) with total == 0.
      final sale = await LocalSaleService(db, const UuidV7Generator()).createSale(
        SaleDraft(
          shopId: f.shopId,
          cashierId: f.ownerId,
          deviceId: f.deviceA,
          lines: [SaleLineDraft(productId: f.freeProductId, quantity: 1000)],
          payments: const [
            SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 0),
          ],
        ),
      );
      final summary = await _retryForever(db, f, 6);
      final onServer = await psql("select count(*) from sales where id='${sale.saleId}'");
      // ignore: avoid_print
      print('F3_ZERO_EVIDENCE local sale=${sale.saleId} grand=${sale.grandTotalMinor} on server=$onServer | $summary');
      expect(summary, contains('eligible for automatic retry after 30 days: false'));
    },
    skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
  );

  test(
    'F-3 cross-device credit limit: second offline Udhaar sale is recorded or flagged, never retried forever',
    () async {
      final f = ShopFixture();
      await f.seedServer(creditLimit: 30000); // Rs 300 limit
      final a = await f.openDevice(creditLimit: 30000);
      final b = await f.openDevice(creditLimit: 30000);
      addTearDown(a.close);
      addTearDown(b.close);
      Future<String> credit(AppDatabase db, String device) async =>
          (await LocalSaleService(db, const UuidV7Generator()).createSale(
            SaleDraft(
              shopId: f.shopId,
              cashierId: f.ownerId,
              deviceId: device,
              customerId: f.customerId,
              lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
              payments: const [
                SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 18000),
              ],
            ),
          )).saleId;
      // Both devices are offline and each sees balance 0 < limit.
      final saleA = await credit(a, f.deviceA);
      final saleB = await credit(b, f.deviceB);
      final summaryA = await _retryForever(a, f, 1);
      final summaryB = await _retryForever(b, f, 6);
      final serverBalance = await serverScalar(
        "select coalesce(sum(amount),0) from customer_ledger_entries where customer_id='${f.customerId}'",
      );
      // ignore: avoid_print
      print('''
F3_CREDIT_EVIDENCE
  A sale $saleA on server: ${await psql("select count(*) from sales where id='$saleA'")} | $summaryA
  B sale $saleB on server: ${await psql("select count(*) from sales where id='$saleB'")} | $summaryB
  local Udhaar A/B: ${await localBalance(a, f.customerId)} / ${await localBalance(b, f.customerId)}   server Udhaar: $serverBalance
''');
      final bOnServer = await psql("select count(*) from sales where id='$saleB'");
      expect(
        bOnServer == '1' || summaryB.contains('eligible for automatic retry after 30 days: false'),
        isTrue,
      );
    },
    skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
  );
}
