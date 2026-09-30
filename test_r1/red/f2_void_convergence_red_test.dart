// R1 Stage A reproduction of audit finding F-2 (void double-count via pull).
// Asserts the CORRECT invariant, so it FAILS on the current code.
@Tags(['recovery-red'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/direct_db_server.dart';

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('f2');
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });

  test(
    'F-2: voided credit sale converges to opening stock and zero Udhaar on the voiding device',
    () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      const ids = UuidV7Generator();
      final upload = PsqlUploadGateway(f.ownerId);
      final queue = SyncQueueRepository(db, shopId: f.shopId);
      final worker = SyncWorker(
        queue: queue,
        gateway: upload,
        workerId: 'device-A',
      );

      final sale = await LocalSaleService(db, ids).createSale(
        SaleDraft(
          shopId: f.shopId,
          cashierId: f.ownerId,
          deviceId: f.deviceA,
          customerId: f.customerId,
          lines: [SaleLineDraft(productId: f.productId, quantity: 2000)],
          payments: const [
            SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 36000),
          ],
        ),
      );
      expect((await worker.runOnce()).synced, 1, reason: upload.calls.join('\n'));
      // Isolate F-2 from T-1: on a non-UTC device the server stores the sale
      // shifted by the zone offset, and the void is then rejected as outside
      // its window before F-2 can happen. Undo that shift on the scratch
      // server so this device behaves like a UTC device (e.g. CI).
      final offset = DateTime.now().timeZoneOffset.inSeconds;
      if (offset != 0) {
        await psql('''
update sales set created_at = created_at - interval '$offset seconds' where id='${sale.saleId}';
update sale_items set created_at = created_at - interval '$offset seconds' where sale_id='${sale.saleId}';
update sale_payments set created_at = created_at - interval '$offset seconds' where sale_id='${sale.saleId}';
update inventory_movements set created_at = created_at - interval '$offset seconds' where reference_id='${sale.saleId}';
update customer_ledger_entries set created_at = created_at - interval '$offset seconds' where sale_id='${sale.saleId}';
''');
      }

      final stockAfterSale = await localStock(db, f.productId);
      final balanceAfterSale = await localBalance(db, f.customerId);

      final voidId = await LocalSaleVoidService(db, ids).voidSale(
        shopId: f.shopId,
        saleId: sale.saleId,
        ownerId: f.ownerId,
        deviceId: f.deviceA,
        reason: 'wrong item',
      );
      final stockAfterLocalVoid = await localStock(db, f.productId);
      final balanceAfterLocalVoid = await localBalance(db, f.customerId);
      final voidRun = await worker.runOnce();
      final queueRows = await db
          .customSelect(
            'select entity_type, status, retry_count, last_error from sync_operations',
          )
          .get();
      expect(
        voidRun.synced,
        1,
        reason: 'queue: ${queueRows.map((r) => r.data).toList()}',
      );

      final localVoidMovementIds = (await db
              .customSelect(
                "select id from inventory_movements where reference_type='sale_void' order by id",
              )
              .get())
          .map((r) => r.read<String>('id'))
          .toList();
      final localRefundIds = (await db
              .customSelect(
                "select id from customer_ledger_entries where type='refund' order by id",
              )
              .get())
          .map((r) => r.read<String>('id'))
          .toList();
      final serverVoidMovementIds = await psql(
        "select string_agg(id::text, ',' order by id) from inventory_movements where reference_id='$voidId'",
      );
      final serverRefundIds = await psql(
        "select string_agg(id::text, ',' order by id) from customer_ledger_entries where type='refund' and sale_id='${sale.saleId}'",
      );

      final pull = ReferencePullService(
        db,
        PsqlPullGateway(f.ownerId),
        shopId: f.shopId,
      );
      await pull.pull(PullEntity.inventoryMovements);
      await pull.pull(PullEntity.customerLedgerEntries);

      final stockAfterPull = await localStock(db, f.productId);
      final balanceAfterPull = await localBalance(db, f.customerId);
      final returnInRows = await db
          .customSelect(
            "select count(*) c from inventory_movements where type='returnIn'",
          )
          .getSingle();
      final refundRows = await db
          .customSelect(
            "select count(*) c from customer_ledger_entries where type='refund'",
          )
          .getSingle();
      final serverStock = await serverScalar(
        "select sum(quantity) from inventory_movements where product_id='${f.productId}'",
      );
      final serverBalance = await serverScalar(
        "select coalesce(sum(case when type in ('openingBalance','creditSale','adjustment') then amount else -amount end),0) from customer_ledger_entries where customer_id='${f.customerId}'",
      );

      // ignore: avoid_print
      print('''
F2_EVIDENCE
  void id                         $voidId
  local void movement ids         $localVoidMovementIds
  server void movement ids        [$serverVoidMovementIds]
  local refund ledger ids         $localRefundIds
  server refund ledger ids        [$serverRefundIds]
  stock   opening/sale/localVoid/afterPull/server  ${ShopFixture.openingStock}/$stockAfterSale/$stockAfterLocalVoid/$stockAfterPull/$serverStock
  udhaar  sale/localVoid/afterPull/server          $balanceAfterSale/$balanceAfterLocalVoid/$balanceAfterPull/$serverBalance
  local returnIn rows after pull  ${returnInRows.read<int>('c')}
  local refund rows after pull    ${refundRows.read<int>('c')}
  rpc calls                       ${upload.calls}
''');

      // Correct convergence: device equals server equals pre-sale state.
      expect(stockAfterPull, serverStock);
      expect(stockAfterPull, ShopFixture.openingStock);
      expect(balanceAfterPull, serverBalance);
      expect(balanceAfterPull, 0);
      expect(returnInRows.read<int>('c'), 1);
      expect(refundRows.read<int>('c'), 1);
    },
    skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
  );
}
