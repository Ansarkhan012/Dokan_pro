// R1.2 timestamp correctness (T-1), server layer: the instant PostgreSQL
// stores equals the real event instant, checked in SQL with PostgreSQL's own
// time-zone rules (independent of the Dart conversion under test). Run under
// TZ=UTC, Asia/Karachi and EST5.
//
// 'T-1: synced sale keeps its real instant on the server' moved here from
// red/t1_timestamp_shift_red_test.dart by R1.2, name and assertion unchanged.
@Tags(['r1-direct-db'])
library;

import 'dart:convert';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/purchases/local_purchase_service.dart';
import 'package:dukaan_pro/features/purchases/purchase_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/direct_db_server.dart';

Future<CreatedSale> _sell(AppDatabase db, ShopFixture f, DateTime at) =>
    LocalSaleService(db, const UuidV7Generator(), clock: () => at).createSale(SaleDraft(
      shopId: f.shopId,
      cashierId: f.ownerId,
      deviceId: f.deviceA,
      lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
      payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000)],
    ));

Future<void> _upload(AppDatabase db, ShopFixture f) async {
  final result = await SyncWorker(
    queue: SyncQueueRepository(db, shopId: f.shopId),
    gateway: PsqlUploadGateway(f.ownerId),
    workerId: 'device-A',
  ).runOnce();
  final ops = await db.select(db.syncOperations).get();
  expect(result.failed, 0, reason: ops.map((o) => '${o.entityType}: ${o.lastError}').join('\n'));
}

/// Stored instant rendered by PostgreSQL itself: UTC, Pakistan wall clock, epoch.
Future<String> _serverTimes(String table, String where) => psql(
      "select string_agg(distinct to_char(created_at at time zone 'UTC','YYYY-MM-DD HH24:MI:SS') || ' UTC | ' || "
      "to_char(created_at at time zone 'Asia/Karachi','YYYY-MM-DD HH24:MI:SS') || ' PKT | ' || "
      "extract(epoch from created_at)::bigint, ' ; ') from $table where $where",
    );

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('t1');
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });
  const skip = r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker';

  // Moved unchanged from the expected-red suite (T-1 fixed by R1.2).
  test(
    'T-1: synced sale keeps its real instant on the server',
    () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      final soldAt = DateTime.now().toUtc();
      final sale = await LocalSaleService(db, const UuidV7Generator(), clock: () => soldAt)
          .createSale(
        SaleDraft(
          shopId: f.shopId,
          cashierId: f.ownerId,
          deviceId: f.deviceA,
          lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
          payments: const [
            SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000),
          ],
        ),
      );
      final queued = await db.select(db.syncOperations).getSingle();
      final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
      final queuedCreatedAt = (payload['sale'] as Map)['createdAt'];
      final uploadedCreatedAt =
          (normalizeSalePayloadForCloud(payload)['sale'] as Map)['createdAt'];
      await SyncWorker(
        queue: SyncQueueRepository(db, shopId: f.shopId),
        gateway: PsqlUploadGateway(f.ownerId),
        workerId: 'device-A',
      ).runOnce();
      final serverCreatedAt = DateTime.parse(
        await psql(
          "select to_json(created_at)#>>'{}' from sales where id='${sale.saleId}'",
        ),
      ).toUtc();
      final serverMovementAt = DateTime.parse(
        await psql(
          "select to_json(min(created_at))#>>'{}' from inventory_movements where reference_id='${sale.saleId}'",
        ),
      ).toUtc();
      final skew = serverCreatedAt.difference(soldAt);
      // ignore: avoid_print
      print('''
T1_EVIDENCE
  device time zone        ${DateTime.now().timeZoneName} (offset ${DateTime.now().timeZoneOffset})
  real sale instant (UTC) ${soldAt.toIso8601String()}
  queued payload createdAt $queuedCreatedAt
  uploaded createdAt      $uploadedCreatedAt
  server sales.created_at ${serverCreatedAt.toIso8601String()}
  server movement created ${serverMovementAt.toIso8601String()}
  server - real           $skew
''');
      expect(skew.inSeconds.abs(), lessThanOrEqualTo(1));
    },
    skip: skip,
  );

  test('A: a 10:00 Pakistan sale is stored as 05:00 UTC in every server row', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final sale = await _sell(db, f, DateTime.utc(2026, 9, 30, 5));
    await _upload(db, f);
    const expected = '2026-09-30 05:00:00 UTC | 2026-09-30 10:00:00 PKT | 1790744400';
    for (final (table, where) in [
      ('sales', "id='${sale.saleId}'"),
      ('sale_items', "sale_id='${sale.saleId}'"),
      ('sale_payments', "sale_id='${sale.saleId}'"),
      ('inventory_movements', "reference_id='${sale.saleId}'"),
    ]) {
      expect(await _serverTimes(table, where), expected, reason: table);
    }
  }, skip: skip);

  test('C: a sale at 00:30 Pakistan is 19:30 UTC the previous calendar day on the server', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final sale = await _sell(db, f, DateTime.utc(2026, 9, 30, 19, 30));
    await _upload(db, f);
    expect(
      await _serverTimes('sales', "id='${sale.saleId}'"),
      '2026-09-30 19:30:00 UTC | 2026-10-01 00:30:00 PKT | 1790796600',
    );
  }, skip: skip);

  test('A: a 10:00 Pakistan purchase is stored as 05:00 UTC on the server', () async {
    final f = ShopFixture();
    await f.seedServer();
    final supplierId = const Uuid().v4();
    await psql("insert into public.suppliers(id,shop_id,name,created_at,updated_at) "
        "values('$supplierId','${f.shopId}','Supplier',now(),now());");
    final db = await f.openDevice();
    addTearDown(db.close);
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(
      id: supplierId, shopId: f.shopId, name: 'Supplier',
      createdAt: f.seededAt, updatedAt: f.seededAt,
    ));
    final purchase = await LocalPurchaseService(db, const UuidV7Generator(),
            clock: () => DateTime.utc(2026, 9, 30, 5))
        .create(PurchaseDraft(
      shopId: f.shopId,
      supplierId: supplierId,
      deviceId: f.deviceA,
      ownerId: f.ownerId,
      lines: [PurchaseLineDraft(productId: f.productId, quantity: 2000, unitCostMinor: 15000)],
      payments: const [PurchasePaymentDraft(method: PaymentMethod.cash, amountMinor: 10000)],
    ));
    await _upload(db, f);
    const expected = '2026-09-30 05:00:00 UTC | 2026-09-30 10:00:00 PKT | 1790744400';
    expect(await _serverTimes('purchases', "id='${purchase.purchaseId}'"), expected);
    expect(await _serverTimes('inventory_movements', "reference_id='${purchase.purchaseId}'"), expected);
  }, skip: skip);

  test('G: the server accepts a void 14 minutes after a Pakistan sale (window on real instants)', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final soldAt = DateTime.utc(2026, 9, 30, 5);
    final sale = await _sell(db, f, soldAt);
    await _upload(db, f);
    final voidId = await LocalSaleVoidService(db, const UuidV7Generator(),
            clock: () => soldAt.add(const Duration(minutes: 14)))
        .voidSale(shopId: f.shopId, saleId: sale.saleId, ownerId: f.ownerId, deviceId: f.deviceA, reason: 'wrong');
    await _upload(db, f);
    expect(await psql("select count(*) from sale_voids where id='$voidId'"), '1');
    expect(
      await psql("select extract(epoch from v.created_at - s.created_at)::int from sale_voids v "
          "join sales s on s.id=v.original_sale_id where v.id='$voidId'"),
      '840',
    );
  }, skip: skip);
}
