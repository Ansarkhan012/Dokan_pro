// R1.4 upgrade path: a database at the approved R1.3 schema (19 migrations)
// holding a shop's sales, Udhaar, a v2 void and reference data is upgraded
// with the R1.4 migration. Every existing value is unchanged (only the new
// server_seq column appears, 0 for existing rows), a first pull from the
// start delivers all existing rows, and new writes get positions after them.
@Tags(['r1-direct-db'])
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

const _r13MigrationCount = 19;
const _tables = [
  'shops', 'devices', 'categories', 'shop_products', 'customers', 'customer_ledger_entries',
  'inventory_movements', 'sales', 'sale_items', 'sale_payments', 'sale_voids',
];

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('seq_upgrade', _r13MigrationCount);
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });

  test('upgrade from the R1.3 schema keeps every row and value, and existing rows are pulled from the start', () async {
    expect(migrationFiles()[_r13MigrationCount].path, endsWith('202610010001_r1_sync_order.sql'));
    final f = ShopFixture();
    await f.seedServer();
    final a = await f.openDevice();
    addTearDown(a.close);
    Future<void> upload() async => expect((await SyncWorker(
          queue: SyncQueueRepository(a, shopId: f.shopId),
          gateway: PsqlUploadGateway(f.ownerId),
          workerId: 'device-A',
        ).runOnce(limit: 50)).failed, 0);
    Future<String> sell({bool credit = false}) async =>
        (await LocalSaleService(a, const UuidV7Generator()).createSale(SaleDraft(
          shopId: f.shopId,
          cashierId: f.ownerId,
          deviceId: f.deviceA,
          customerId: credit ? f.customerId : null,
          lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
          payments: [SalePaymentDraft(method: credit ? PaymentMethod.credit : PaymentMethod.cash, amountMinor: 18000)],
        )))
            .saleId;
    await sell(credit: true);
    final voided = await sell();
    await upload();
    await LocalSaleVoidService(a, const UuidV7Generator())
        .voidSale(shopId: f.shopId, saleId: voided, ownerId: f.ownerId, deviceId: f.deviceA, reason: 'wrong');
    await upload();

    // Content of every table, without the column the upgrade adds.
    final contentSql = [
      for (final t in _tables)
        "select '$t:' || count(*) || ':' || md5(coalesce(string_agg((to_jsonb(x) - 'server_seq')::text, '|' "
            "order by (to_jsonb(x)->>'id')), '')) from public.$t x",
    ].join(' union all ');
    Future<String> content() => psql('$contentSql;');
    final before = await content();

    for (final file in migrationFiles().skip(_r13MigrationCount).take(1)) {
      await psql(file.readAsStringSync());
    }

    expect(await content(), before, reason: 'no existing value changed');
    for (final t in _tables) {
      expect(await psql('select count(*) from public.$t where server_seq <> 0'), '0', reason: '$t existing rows');
    }
    // A device whose cursor predates R1.4 pulls from the start and gets them all.
    final b = await f.openDevice();
    addTearDown(b.close);
    final pull = ReferencePullService(b, PsqlPullGateway(f.ownerId), shopId: f.shopId);
    for (final entity in [PullEntity.sales, PullEntity.saleVoids, PullEntity.inventoryMovements, PullEntity.customerLedgerEntries]) {
      await pull.pull(entity, pageSize: 2);
    }
    for (final t in ['sales', 'sale_voids', 'inventory_movements', 'customer_ledger_entries']) {
      final local = (await b.customSelect('select count(*) c from $t').getSingle()).read<int>('c');
      expect(local, int.parse(await psql("select count(*) from $t where shop_id='${f.shopId}'")), reason: t);
    }
    // New writes are positioned after every existing row and reach b.
    final later = await sell();
    await upload();
    expect(int.parse(await psql("select server_seq from sales where id='$later'")), greaterThan(0));
    expect(await pull.pull(PullEntity.sales), 1);
  }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');
}
