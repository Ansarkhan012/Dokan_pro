// R1.4 pilot simulation: 10 shops, two devices each, on the real migrated
// schema. Devices go offline, one runs a slow clock, one a fast clock, sales
// (cash and Udhaar) and voids are uploaded late and in mixed order, and both
// devices pull repeatedly. Afterwards every device equals PostgreSQL for its
// own shop, no row of another shop exists on any device, and no financial
// effect is duplicated. Correctness and isolation, not load.
@Tags(['r1-direct-db'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/direct_db_server.dart';

const _shops = 10;
const _entities = [
  PullEntity.sales,
  PullEntity.saleItems,
  PullEntity.salePayments,
  PullEntity.saleVoids,
  PullEntity.inventoryMovements,
  PullEntity.customerLedgerEntries,
];

final class _Shop {
  _Shop(this.f, this.a, this.b);
  final ShopFixture f;
  final AppDatabase a, b;
}

Future<String> _sell(AppDatabase db, ShopFixture f, String device, DateTime at, {required bool credit}) async =>
    (await LocalSaleService(db, const UuidV7Generator(), clock: () => at).createSale(SaleDraft(
      shopId: f.shopId,
      cashierId: f.ownerId,
      deviceId: device,
      customerId: credit ? f.customerId : null,
      lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
      payments: [SalePaymentDraft(method: credit ? PaymentMethod.credit : PaymentMethod.cash, amountMinor: 18000)],
    )))
        .saleId;

Future<void> _upload(AppDatabase db, ShopFixture f, String worker) async {
  final result = await SyncWorker(
    queue: SyncQueueRepository(db, shopId: f.shopId),
    gateway: PsqlUploadGateway(f.ownerId),
    workerId: worker,
  ).runOnce(limit: 100);
  expect(result.failed, 0);
}

Future<void> _pull(AppDatabase db, ShopFixture f) async {
  final pull = ReferencePullService(db, PsqlPullGateway(f.ownerId), shopId: f.shopId);
  for (final entity in _entities) {
    await pull.pull(entity, pageSize: 4);
  }
}

/// Everything that must converge for one shop, as one comparable string.
Future<String> _deviceState(AppDatabase db, ShopFixture f) async {
  Future<String> ids(String sql) async =>
      (await db.customSelect(sql).get()).map((r) => r.data.values.join(':')).join(',');
  return [
    await ids("select id from sales where shop_id='${f.shopId}' order by id"),
    await ids("select id from sale_voids where shop_id='${f.shopId}' order by id"),
    await ids("select id, quantity from inventory_movements where shop_id='${f.shopId}' order by id"),
    await ids("select id, type, amount from customer_ledger_entries where shop_id='${f.shopId}' order by id"),
    await localStock(db, f.productId),
    await localBalance(db, f.customerId),
  ].join(' | ');
}

Future<String> _serverState(ShopFixture f) async {
  Future<String> ids(String sql) async => (await psql(sql)).replaceAll('\n', ',');
  return [
    await ids("select id from sales where shop_id='${f.shopId}' order by id"),
    await ids("select id from sale_voids where shop_id='${f.shopId}' order by id"),
    await ids("select id || ':' || quantity from inventory_movements where shop_id='${f.shopId}' order by id"),
    await ids("select id || ':' || type || ':' || amount from customer_ledger_entries where shop_id='${f.shopId}' order by id"),
    await serverScalar("select coalesce(sum(quantity),0) from inventory_movements where product_id='${f.productId}'"),
    await serverScalar("select coalesce(sum(case when type in ('openingBalance','creditSale','adjustment') "
        "then amount else -amount end),0) from customer_ledger_entries where customer_id='${f.customerId}'"),
  ].join(' | ');
}

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('ten_shops');
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });

  test('10 shops x 2 devices: offline, skewed clocks and late uploads converge with no leakage or duplicates', () async {
    final now = DateTime.now().toUtc();
    final shops = <_Shop>[];
    for (var i = 0; i < _shops; i++) {
      final f = ShopFixture();
      await f.seedServer();
      shops.add(_Shop(f, await f.openDevice(), await f.openDevice()));
    }
    addTearDown(() async {
      for (final s in shops) {
        await s.a.close();
        await s.b.close();
      }
    });
    final expectedSales = <String, int>{};

    // Round 1: device A of every shop is offline and sells with a slow clock
    // (2 h behind); device B sells with a fast clock (1 day ahead), uploads
    // at once and pulls.
    for (final (i, s) in shops.indexed) {
      for (var k = 0; k < 2; k++) {
        await _sell(s.a, s.f, s.f.deviceA, now.subtract(Duration(hours: 2, minutes: k)), credit: (i + k).isEven);
      }
      await _sell(s.b, s.f, s.f.deviceB, now.add(const Duration(days: 1)), credit: i.isOdd);
      await _upload(s.b, s.f, 'B-$i');
      await _pull(s.b, s.f);
      expectedSales[s.f.shopId] = 3;
    }
    // Round 2: B sells normally (behind its own earlier future row) and
    // uploads; A comes online late, uploads its old sales, voids its newest
    // sale in some shops, and both pull twice in mixed order.
    for (final (i, s) in shops.indexed) {
      final normal = await _sell(s.b, s.f, s.f.deviceB, now, credit: i.isEven);
      await _upload(s.b, s.f, 'B-$i');
      if (i % 3 == 0) {
        await LocalSaleVoidService(s.b, const UuidV7Generator(), clock: () => now.add(const Duration(minutes: 3)))
            .voidSale(shopId: s.f.shopId, saleId: normal, ownerId: s.f.ownerId, deviceId: s.f.deviceB, reason: 'wrong');
        await _upload(s.b, s.f, 'B-$i');
      }
      expectedSales[s.f.shopId] = expectedSales[s.f.shopId]! + 1;
    }
    for (final (i, s) in shops.reversed.indexed) {
      await _upload(s.a, s.f, 'A-$i');
    }
    for (final s in shops) {
      await _pull(s.a, s.f);
      await _pull(s.b, s.f);
      await _pull(s.b, s.f);
      await _pull(s.a, s.f);
    }

    // Convergence, isolation and single financial effects, shop by shop.
    final allShopIds = shops.map((s) => s.f.shopId).toSet();
    for (final (i, s) in shops.indexed) {
      final server = await _serverState(s.f);
      expect(await _deviceState(s.a, s.f), server, reason: 'shop $i device A');
      expect(await _deviceState(s.b, s.f), server, reason: 'shop $i device B');
      expect(await serverScalar("select count(*) from sales where shop_id='${s.f.shopId}'"), expectedSales[s.f.shopId]);
      for (final db in [s.a, s.b]) {
        for (final table in ['sales', 'sale_items', 'sale_payments', 'inventory_movements', 'customer_ledger_entries', 'sale_voids']) {
          final foreign = await db.customSelect(
            'select count(*) c from $table where shop_id not in (${allShopIds.map((id) => "'$id'").join(',')}) '
            "or shop_id<>'${s.f.shopId}'",
          ).getSingle();
          expect(foreign.read<int>('c'), 0, reason: 'shop $i $table holds another shop\'s rows');
        }
        // Exactly one sale movement per sale item and at most one void compensation per item.
        final perSale = await db.customSelect(
          "select count(*) c from sale_items i where i.shop_id='${s.f.shopId}' and "
          "(select count(*) from inventory_movements m where m.reference_id=i.sale_id and m.product_id=i.product_id and m.type='sale')<>1",
        ).getSingle();
        expect(perSale.read<int>('c'), 0, reason: 'shop $i duplicate or missing sale movement');
        final voidMoves = await db.customSelect(
          "select count(*) c from sale_voids v where v.shop_id='${s.f.shopId}' and "
          "(select count(*) from inventory_movements m where m.reference_id=v.id)<>1",
        ).getSingle();
        expect(voidMoves.read<int>('c'), 0, reason: 'shop $i duplicate or missing void compensation');
      }
    }
    // ignore: avoid_print
    print('TEN_SHOP_EVIDENCE shops=$_shops sales=${expectedSales.values.fold(0, (a, b) => a + b)} '
        'voids=${await psql("select count(*) from sale_voids where shop_id in (${allShopIds.map((id) => "'$id'").join(',')})")} '
        'counters=${await psql("select string_agg(last_seq::text, ',' order by last_seq) from shop_sync_state where shop_id in (${allShopIds.map((id) => "'$id'").join(',')})")}');
  }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
      timeout: const Timeout(Duration(minutes: 20)));
}
