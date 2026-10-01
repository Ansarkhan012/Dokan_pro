// R1.4 server-owned sync order against the real migrated PostgreSQL schema:
// every pulled row carries server_seq (one value per transaction and shop,
// assigned by the server, never by the client), and devices pull by the
// cursor (server_seq, id). Covers the counter's prefix property, identical
// and microsecond timestamps, pagination, restart mid-pull, repeated pages,
// shop isolation, global categories and every pulled entity type.
@Tags(['r1-direct-db'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/local_customer_payment_service.dart';
import 'package:dukaan_pro/features/expenses/expense_models.dart';
import 'package:dukaan_pro/features/expenses/local_expense_service.dart';
import 'package:dukaan_pro/features/purchases/local_purchase_service.dart';
import 'package:dukaan_pro/features/purchases/local_supplier_payment_service.dart';
import 'package:dukaan_pro/features/purchases/purchase_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/direct_db_server.dart';

String _uuid() => const Uuid().v4();

/// Counts fetches; can fail on a given fetch, or deliver one page twice.
final class _Probe implements ReferencePullGateway {
  _Probe(this.inner, {this.failOnFetch, this.repeatFetch});
  final ReferencePullGateway inner;
  final int? failOnFetch;
  final int? repeatFetch;
  int fetches = 0;
  List<RemoteChange>? _last;

  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    fetches++;
    if (fetches == failOnFetch) throw const SocketException('simulated drop mid-pull');
    if (fetches == repeatFetch && _last != null) return _last!; // a retried, already-applied page
    return _last = await inner.fetch(entity: entity, shopId: shopId, after: after, limit: limit);
  }
}

Future<String> _sell(AppDatabase db, ShopFixture f, DateTime at, {String? device, bool credit = false}) async =>
    (await LocalSaleService(db, const UuidV7Generator(), clock: () => at).createSale(SaleDraft(
      shopId: f.shopId,
      cashierId: f.ownerId,
      deviceId: device ?? f.deviceA,
      customerId: credit ? f.customerId : null,
      lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
      payments: [SalePaymentDraft(method: credit ? PaymentMethod.credit : PaymentMethod.cash, amountMinor: 18000)],
    )))
        .saleId;

Future<void> _upload(AppDatabase db, ShopFixture f) async {
  final result = await SyncWorker(
    queue: SyncQueueRepository(db, shopId: f.shopId),
    gateway: PsqlUploadGateway(f.ownerId),
    workerId: 'device-${f.shopId}',
  ).runOnce(limit: 200);
  final failed = await (db.select(db.syncOperations)..where((t) => t.status.equals('failed'))).get();
  expect(result.failed, 0, reason: failed.map((o) => '${o.entityType}: ${o.lastError}').join('\n'));
}

Future<int> _local(AppDatabase db, String table, [String where = '1=1']) async =>
    (await db.customSelect('select count(*) c from $table where $where').getSingle()).read<int>('c');

Future<int> _server(String table, String where) async => int.parse(await psql('select count(*) from $table where $where'));

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('seq');
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });
  const skip = r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker';

  test('server_seq: one value per transaction, forged values ignored, a replay consumes nothing', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final saleId = await _sell(db, f, DateTime.now().toUtc(), credit: true);
    await _upload(db, f);
    final seqs = await psql('''
select string_agg(distinct server_seq::text, ',') from (
  select server_seq from sales where id='$saleId'
  union all select server_seq from sale_items where sale_id='$saleId'
  union all select server_seq from sale_payments where sale_id='$saleId'
  union all select server_seq from inventory_movements where reference_id='$saleId'
  union all select server_seq from customer_ledger_entries where sale_id='$saleId') x;''');
    expect(seqs.split(','), hasLength(1), reason: 'one checkout, one transaction, one value: $seqs');
    expect(int.parse(seqs), greaterThan(0));

    final counter = await psql("select last_seq from shop_sync_state where shop_id='${f.shopId}'");
    final payload = jsonDecode((await db.select(db.syncOperations).getSingle()).payload) as Map<String, dynamic>;
    final replay = PsqlUploadGateway(f.ownerId);
    await replay.uploadSaleAggregate(payload);
    expect(replay.calls.single, contains('already_synced'));
    expect(await psql("select last_seq from shop_sync_state where shop_id='${f.shopId}'"), counter);

    final forgedId = _uuid();
    await psql("insert into customers(id,shop_id,name,created_at,updated_at,server_seq) "
        "values('$forgedId','${f.shopId}','Forged',now(),now(),999999);");
    final forged = int.parse(await psql("select server_seq from customers where id='$forgedId'"));
    expect(forged, int.parse(counter) + 1);
    await psql("update customers set server_seq=-5, name='Renamed' where id='$forgedId';");
    expect(int.parse(await psql("select server_seq from customers where id='$forgedId'")), forged + 1,
        reason: 'an update gets a new, server-assigned position');
  }, skip: skip);

  test('server_seq: a waiting writer and a rolled-back writer keep committed values a gap-free prefix', () async {
    final f = ShopFixture();
    await f.seedServer();
    final base = int.parse(await psql(
        "select coalesce((select last_seq from shop_sync_state where shop_id='${f.shopId}'),0)"));
    String insert(String name) =>
        "insert into customers(id,shop_id,name,created_at,updated_at) values('${_uuid()}','${f.shopId}','$name',now(),now());";
    // Holder: takes the shop counter, then rolls back after 2 s.
    final rolledBack = psql('begin; ${insert('rolled back')} select pg_sleep(2); rollback;');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final watch = Stopwatch()..start();
    // Waiter: must wait for the holder, then reuses its number.
    final waiter = psql('begin; ${insert('committed')} commit;');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final visibleWhileHeld = await psql(
        "select count(*) from customers where shop_id='${f.shopId}' and server_seq>$base");
    await Future.wait([rolledBack, waiter]);
    watch.stop();
    expect(visibleWhileHeld, '0', reason: 'nothing is visible while the counter is held');
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 800)), reason: 'the waiter waited');
    expect(await psql("select string_agg(name || ':' || (server_seq-$base), ',') from customers "
        "where shop_id='${f.shopId}' and server_seq>$base"), 'committed:1', reason: 'no gap after a rollback');
  }, skip: skip);

  test('identical timestamps: 12 sales in one second are pulled exactly once over pages of 5', () async {
    final f = ShopFixture();
    await f.seedServer();
    final a = await f.openDevice();
    final b = await f.openDevice();
    addTearDown(a.close);
    addTearDown(b.close);
    final sameSecond = DateTime.utc(2026, 9, 30, 10);
    final ids = [for (var i = 0; i < 12; i++) await _sell(a, f, sameSecond)];
    await _upload(a, f);
    expect(await psql("select count(distinct created_at) from sales where shop_id='${f.shopId}'"), '1');
    final probe = _Probe(PsqlPullGateway(f.ownerId));
    expect(await ReferencePullService(b, probe, shopId: f.shopId).pull(PullEntity.sales, pageSize: 5), 12);
    expect(probe.fetches, 3);
    for (final id in ids) {
      expect(await _local(b, 'sales', "id='$id'"), 1);
    }
    final again = _Probe(PsqlPullGateway(f.ownerId));
    expect(await ReferencePullService(b, again, shopId: f.shopId).pull(PullEntity.sales, pageSize: 5), 0);
    expect(again.fetches, 1);
  }, skip: skip);

  test('T-1b on the real server: microsecond timestamps within one second neither loop nor skip', () async {
    final f = ShopFixture();
    await f.seedServer();
    final b = await f.openDevice();
    addTearDown(b.close);
    // Seven movements in the same second, microseconds apart; three share one
    // transaction (same server_seq, ordered by id), four are separate.
    final rows = [for (var i = 1; i <= 7; i++) (_uuid(), '2026-09-30 10:00:00.${(100000 + i * 7).toString()}+00')];
    String row((String, String) r) => "('${r.$1}','${f.shopId}','${f.productId}','manualAdjustment',-1,'${f.ownerId}','${r.$2}')";
    const cols = 'insert into inventory_movements(id,shop_id,product_id,type,quantity,created_by,created_at) values';
    await psql('begin; $cols ${rows.take(3).map(row).join(',')}; commit;');
    for (final r in rows.skip(3)) {
      await psql('$cols ${row(r)};');
    }
    final probe = _Probe(PsqlPullGateway(f.ownerId));
    final applied = await ReferencePullService(b, probe, shopId: f.shopId)
        .pull(PullEntity.inventoryMovements, pageSize: 2);
    expect(applied, 8, reason: 'opening movement + 7');
    expect(probe.fetches, lessThanOrEqualTo(5), reason: 'bounded: 8 rows / 2 per page');
    for (final r in rows) {
      expect(await _local(b, 'inventory_movements', "id='${r.$1}'"), 1);
    }
    final cursor = await b.select(b.syncCursors).getSingle();
    expect(cursor.serverSeq, int.parse(await psql(
        "select max(server_seq) from inventory_movements where shop_id='${f.shopId}'")));
  }, skip: skip);

  test('restart halfway through a pull resumes from the last committed page, with no duplicates', () async {
    final f = ShopFixture();
    await f.seedServer();
    final a = await f.openDevice();
    addTearDown(a.close);
    for (var i = 0; i < 23; i++) {
      await _sell(a, f, DateTime.utc(2026, 9, 30, 10, i));
    }
    await _upload(a, f);
    final dir = Directory.systemTemp.createTempSync('r1_4_restart_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}b.sqlite');
    final b = await f.openDevice(file: file);
    final failing = _Probe(PsqlPullGateway(f.ownerId), failOnFetch: 4);
    await expectLater(
      ReferencePullService(b, failing, shopId: f.shopId).pull(PullEntity.sales, pageSize: 4),
      throwsA(isA<SocketException>()),
    );
    expect(await _local(b, 'sales'), 12, reason: 'three committed pages');
    await b.close(); // the app is killed

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final resumed = _Probe(PsqlPullGateway(f.ownerId));
    expect(await ReferencePullService(reopened, resumed, shopId: f.shopId).pull(PullEntity.sales, pageSize: 4), 11);
    expect(resumed.fetches, 3, reason: 'resumes after page 3, not from zero');
    expect(await _local(reopened, 'sales'), 23);
    expect(await _local(reopened, 'sales'), await _server('sales', "shop_id='${f.shopId}'"));
  }, skip: skip);

  test('a repeated page (retried response) is applied idempotently', () async {
    final f = ShopFixture();
    await f.seedServer();
    final a = await f.openDevice();
    final b = await f.openDevice();
    addTearDown(a.close);
    addTearDown(b.close);
    for (var i = 0; i < 9; i++) {
      await _sell(a, f, DateTime.utc(2026, 9, 30, 11, i), credit: i.isEven);
    }
    await _upload(a, f);
    for (final entity in [PullEntity.sales, PullEntity.inventoryMovements, PullEntity.customerLedgerEntries]) {
      final probe = _Probe(PsqlPullGateway(f.ownerId), repeatFetch: 2);
      await ReferencePullService(b, probe, shopId: f.shopId).pull(entity, pageSize: 3);
    }
    expect(await _local(b, 'sales'), 9);
    expect(await _local(b, 'inventory_movements'), await _server('inventory_movements', "shop_id='${f.shopId}'"));
    expect(await _local(b, 'customer_ledger_entries'),
        await _server('customer_ledger_entries', "shop_id='${f.shopId}'"));
    expect(await localStock(b, f.productId),
        await serverScalar("select sum(quantity) from inventory_movements where product_id='${f.productId}'"));
    expect(await localBalance(b, f.customerId), 5 * 18000);
  }, skip: skip);

  test('shop isolation: devices never receive another shop\'s rows; counters are independent', () async {
    final f = ShopFixture();
    final g = ShopFixture();
    await f.seedServer();
    await g.seedServer();
    final af = await f.openDevice();
    final ag = await g.openDevice();
    addTearDown(af.close);
    addTearDown(ag.close);
    for (var i = 0; i < 3; i++) {
      await _sell(af, f, DateTime.utc(2026, 9, 30, 12, i));
      await _sell(ag, g, DateTime.utc(2026, 9, 30, 12, i));
    }
    await _upload(af, f);
    await _upload(ag, g);
    final bf = await f.openDevice();
    addTearDown(bf.close);
    for (final entity in [PullEntity.sales, PullEntity.saleItems, PullEntity.inventoryMovements]) {
      await ReferencePullService(bf, PsqlPullGateway(f.ownerId), shopId: f.shopId).pull(entity);
    }
    expect(await _local(bf, 'sales', "shop_id<>'${f.shopId}'"), 0);
    expect(await _local(bf, 'inventory_movements', "shop_id<>'${f.shopId}'"), 0);
    expect(await _local(bf, 'sales'), 3);
    // f's owner asking for g's rows gets nothing (RLS), whatever the cursor.
    expect(await PsqlPullGateway(f.ownerId).fetch(entity: PullEntity.sales, shopId: g.shopId), isEmpty);
    expect(await psql("select count(*) from shop_sync_state where shop_id in ('${f.shopId}','${g.shopId}')"), '2');
  }, skip: skip);

  test('global and shop categories have separate cursors, so a later global row is not skipped', () async {
    final f = ShopFixture();
    await f.seedServer();
    final b = await f.openDevice();
    addTearDown(b.close);
    final pull = ReferencePullService(b, PsqlPullGateway(f.ownerId), shopId: f.shopId);
    await pull.pull(PullEntity.categories);
    // Shop counter is far ahead of the global one; a new global category must arrive.
    for (var i = 0; i < 5; i++) {
      await psql("insert into categories(id,shop_id,name,created_at,updated_at) values('${_uuid()}','${f.shopId}','Shop $i',now(),now());");
    }
    await pull.pull(PullEntity.categories);
    final globalId = _uuid();
    await psql("insert into categories(id,shop_id,name,created_at,updated_at) values('$globalId',null,'Global ${_uuid()}',now(),now());");
    await pull.pull(PullEntity.categories);
    expect(await _local(b, 'categories', "id='$globalId'"), 1);
    expect(await _local(b, 'categories', "shop_id='${f.shopId}'"),
        await _server('categories', "shop_id='${f.shopId}'"));
  }, skip: skip);

  test('every pulled entity type, including procurement and expenses, converges on a fresh device', () async {
    final f = ShopFixture();
    await f.seedServer();
    final supplierId = _uuid(), expenseCategoryId = _uuid(), cashierId = _uuid();
    final globalCategoryId = _uuid(), masterId = _uuid();
    await psql('''
insert into suppliers(id,shop_id,name,created_at,updated_at) values('$supplierId','${f.shopId}','Supplier',now(),now());
insert into expense_categories(id,shop_id,name) values('$expenseCategoryId','${f.shopId}','Rent');
insert into cashiers(id,shop_id,display_name,login_code,pin_hash) values('$cashierId','${f.shopId}','Ali','ali-$cashierId','x');
insert into categories(id,shop_id,name,created_at,updated_at) values('$globalCategoryId',null,'Global $globalCategoryId',now(),now());
insert into master_products(id,barcode,name,category_id,default_unit,created_at,updated_at)
  values('$masterId','B$masterId','Master','$globalCategoryId','piece',now(),now());''');
    final a = await f.openDevice();
    addTearDown(a.close);
    await a.into(a.suppliers).insert(SuppliersCompanion.insert(
        id: supplierId, shopId: f.shopId, name: 'Supplier', createdAt: f.seededAt, updatedAt: f.seededAt));
    await a.into(a.expenseCategories).insert(ExpenseCategoriesCompanion.insert(
        id: expenseCategoryId, shopId: f.shopId, name: 'Rent', createdAt: f.seededAt, updatedAt: f.seededAt));
    const ids = UuidV7Generator();
    final now = DateTime.now().toUtc();
    await _sell(a, f, now, credit: true);
    await LocalCustomerPaymentService(a, ids).receive(shopId: f.shopId, customerId: f.customerId,
        actorId: f.ownerId, deviceId: f.deviceA, amountMinor: 5000, method: PaymentMethod.cash);
    final voided = await _sell(a, f, now);
    await LocalSaleVoidService(a, ids).voidSale(
        shopId: f.shopId, saleId: voided, ownerId: f.ownerId, deviceId: f.deviceA, reason: 'wrong');
    final returned = await _sell(a, f, now);
    final returnedItem = await (a.select(a.saleItems)..where((t) => t.saleId.equals(returned))).getSingle();
    await LocalSaleReturnService(a, ids).create(SaleReturnDraft(
      shopId: f.shopId, originalSaleId: returned, ownerId: f.ownerId, deviceId: f.deviceA,
      refundMethod: PaymentMethod.cash, reason: 'damaged',
      lines: [SaleReturnLineDraft(originalSaleItemId: returnedItem.id, quantity: 1000)],
    ));
    await LocalPurchaseService(a, ids).create(PurchaseDraft(
      shopId: f.shopId, supplierId: supplierId, deviceId: f.deviceA, ownerId: f.ownerId,
      lines: [PurchaseLineDraft(productId: f.productId, quantity: 5000, unitCostMinor: 15000)],
      payments: const [PurchasePaymentDraft(method: PaymentMethod.cash, amountMinor: 50000)],
    ));
    await LocalSupplierPaymentService(a, ids).record(shopId: f.shopId, supplierId: supplierId,
        ownerId: f.ownerId, deviceId: f.deviceA, amountMinor: 5000, method: PaymentMethod.cash);
    await LocalExpenseService(a, ids).create(ExpenseDraft(
      shopId: f.shopId, categoryId: expenseCategoryId, categoryName: 'Rent', amountMinor: 250000,
      paymentMethod: PaymentMethod.cash, description: 'Shop rent', ownerId: f.ownerId,
      deviceId: f.deviceA, expenseAt: now,
    ));
    await _upload(a, f);

    // A brand-new device with an empty database pulls everything.
    final c = AppDatabase(NativeDatabase.memory());
    addTearDown(c.close);
    final pull = ReferencePullService(c, PsqlPullGateway(f.ownerId), shopId: f.shopId);
    const order = [
      PullEntity.shops, PullEntity.devices, PullEntity.cashiers, PullEntity.categories,
      PullEntity.masterProducts, PullEntity.shopProducts, PullEntity.customers, PullEntity.suppliers,
      PullEntity.expenseCategories, PullEntity.sales, PullEntity.saleItems, PullEntity.salePayments,
      PullEntity.saleReturns, PullEntity.saleReturnItems, PullEntity.saleVoids, PullEntity.purchases,
      PullEntity.purchaseItems, PullEntity.purchasePayments, PullEntity.supplierLedgerEntries,
      PullEntity.customerLedgerEntries, PullEntity.inventoryMovements, PullEntity.expenses,
    ];
    expect(order.toSet().length, PullEntity.values.length - 1, reason: 'every pull entity except the internal global-categories stream');
    for (final entity in order) {
      await pull.pull(entity, pageSize: 3);
    }
    const tables = {
      'shops': 'id', 'devices': 'shop_id', 'cashiers': 'shop_id', 'shop_products': 'shop_id',
      'customers': 'shop_id', 'suppliers': 'shop_id', 'expense_categories': 'shop_id', 'sales': 'shop_id',
      'sale_items': 'shop_id', 'sale_payments': 'shop_id', 'sale_returns': 'shop_id',
      'sale_return_items': 'shop_id', 'sale_voids': 'shop_id', 'purchases': 'shop_id',
      'purchase_items': 'shop_id', 'purchase_payments': 'shop_id', 'supplier_ledger_entries': 'shop_id',
      'customer_ledger_entries': 'shop_id', 'inventory_movements': 'shop_id', 'expenses': 'shop_id',
    };
    for (final entry in tables.entries) {
      final server = await _server(entry.key, "${entry.value}='${f.shopId}'");
      expect(server, greaterThan(0), reason: '${entry.key} has server rows');
      expect(await _local(c, entry.key), server, reason: entry.key);
    }
    expect(await _local(c, 'master_products', "id='$masterId'"), 1);
    expect(await _local(c, 'categories', "id='$globalCategoryId'"), 1);
    expect(await localStock(c, f.productId),
        await serverScalar("select sum(quantity) from inventory_movements where product_id='${f.productId}'"));
    expect(await localBalance(c, f.customerId), 18000 - 5000);
    // A second full pass applies nothing.
    var reapplied = 0;
    for (final entity in order) {
      reapplied += await pull.pull(entity, pageSize: 3);
    }
    expect(reapplied, 0);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
