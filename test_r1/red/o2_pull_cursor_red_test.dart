// R1 Stage A reproduction of audit finding O-2 (client-clock pull cursors).
// Asserts the CORRECT invariant, so it FAILS on the current code.
// T-1 is neutralised with undoZoneShift() so only the cursor defect is tested.
@Tags(['recovery-red'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/direct_db_server.dart';

Future<String> _sell(
  AppDatabase db,
  ShopFixture f,
  String deviceId,
  DateTime at,
) async {
  final sale = await LocalSaleService(db, const UuidV7Generator(), clock: () => at)
      .createSale(
    SaleDraft(
      shopId: f.shopId,
      cashierId: f.ownerId,
      deviceId: deviceId,
      lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
      payments: const [
        SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000),
      ],
    ),
  );
  return sale.saleId;
}

Future<void> _upload(AppDatabase db, ShopFixture f, String worker) async {
  final result = await SyncWorker(
    queue: SyncQueueRepository(db, shopId: f.shopId),
    gateway: PsqlUploadGateway(f.ownerId),
    workerId: worker,
  ).runOnce();
  expect(result.failed, 0);
}

Future<void> _pull(AppDatabase db, ShopFixture f) async {
  final pull = ReferencePullService(db, PsqlPullGateway(f.ownerId), shopId: f.shopId);
  await pull.pull(PullEntity.sales);
  await pull.pull(PullEntity.inventoryMovements);
}

Future<String> _cursor(AppDatabase db) async =>
    (await db.select(db.syncCursors).get())
        .map((c) => '${c.entityType}@${c.updatedAt.toUtc().toIso8601String()}')
        .join(', ');

Future<bool> _has(AppDatabase db, String saleId) async =>
    (await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingleOrNull()) != null;

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('o2');
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });

  test(
    'O-2 scenario A: late offline upload from device A reaches device B',
    () async {
      final f = ShopFixture();
      await f.seedServer();
      final a = await f.openDevice();
      final b = await f.openDevice();
      addTearDown(a.close);
      addTearDown(b.close);
      final now = DateTime.now().toUtc();

      // A sells online at "now"; B pulls and advances its cursor to "now".
      final s1 = await _sell(a, f, f.deviceA, now);
      await _upload(a, f, 'A');
      await undoZoneShift(s1);
      await _pull(b, f);
      final cursorAfterFirstPull = await _cursor(b);

      // A was offline two hours ago; it uploads that older sale only now.
      final s0 = await _sell(a, f, f.deviceA, now.subtract(const Duration(hours: 2)));
      await _upload(a, f, 'A');
      await undoZoneShift(s0);
      await _pull(b, f);

      final onServer = await psql("select count(*) from sales where id='$s0'");
      final bStock = await localStock(b, f.productId);
      final serverStock = await serverScalar(
        "select sum(quantity) from inventory_movements where product_id='${f.productId}'",
      );
      // ignore: avoid_print
      print('''
O2A_EVIDENCE
  B cursor after first pull  $cursorAfterFirstPull
  late sale S0 on server     $onServer (created ${now.subtract(const Duration(hours: 2)).toIso8601String()})
  B has S1 / S0              ${await _has(b, s1)} / ${await _has(b, s0)}
  B cursor after second pull ${await _cursor(b)}
  stock B / server           $bStock / $serverStock
''');
      expect(await _has(b, s0), isTrue);
      expect(bStock, serverStock);
    },
    skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
  );

  test(
    'O-2 scenario B: a future-clock upload does not hide later normal rows from device B',
    () async {
      final f = ShopFixture();
      await f.seedServer();
      final a = await f.openDevice();
      final b = await f.openDevice();
      addTearDown(a.close);
      addTearDown(b.close);
      final now = DateTime.now().toUtc();

      // A's clock is one day fast for one sale.
      final future = await _sell(a, f, f.deviceA, now.add(const Duration(days: 1)));
      await _upload(a, f, 'A');
      await undoZoneShift(future);
      await _pull(b, f);
      final cursorAfterFuture = await _cursor(b);

      // Clock corrected; normal sale at "now".
      final normal = await _sell(a, f, f.deviceA, now);
      await _upload(a, f, 'A');
      await undoZoneShift(normal);
      await _pull(b, f);

      final bStock = await localStock(b, f.productId);
      final serverStock = await serverScalar(
        "select sum(quantity) from inventory_movements where product_id='${f.productId}'",
      );
      // ignore: avoid_print
      print('''
O2B_EVIDENCE
  B cursor after future row  $cursorAfterFuture
  B has future / normal      ${await _has(b, future)} / ${await _has(b, normal)}
  stock B / server           $bStock / $serverStock
''');
      expect(await _has(b, normal), isTrue);
      expect(bStock, serverStock);
    },
    skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
  );
}
