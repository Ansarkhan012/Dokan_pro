// R1.3 (F-2) void convergence against the real migrated PostgreSQL functions:
// the v2 void carries the device's compensation ids, the server validates
// them against its own sale rows and stores exactly those rows, so a pull
// never brings a second copy. v1 voids are refused (DPV01) before any write.
//
// 'F-2: voided credit sale converges ...' moved here from
// red/f2_void_convergence_red_test.dart by R1.3, name and assertions unchanged.
@Tags(['r1-direct-db'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
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
import 'package:uuid/uuid.dart';

import '../support/direct_db_server.dart';

String _uuid() => const Uuid().v4();

Future<CreatedSale> _sell(
  AppDatabase db,
  ShopFixture f, {
  List<SalePaymentDraft> payments = const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 36000)],
  String? customerId,
  DateTime? at,
}) =>
    LocalSaleService(db, const UuidV7Generator(), clock: at == null ? null : () => at).createSale(SaleDraft(
      shopId: f.shopId,
      cashierId: f.ownerId,
      deviceId: f.deviceA,
      customerId: customerId,
      lines: [SaleLineDraft(productId: f.productId, quantity: 2000)],
      payments: payments,
    ));

Future<String> _void(AppDatabase db, ShopFixture f, String saleId, {DateTime? at}) =>
    LocalSaleVoidService(db, const UuidV7Generator(), clock: at == null ? null : () => at)
        .voidSale(shopId: f.shopId, saleId: saleId, ownerId: f.ownerId, deviceId: f.deviceA, reason: 'wrong item');

Future<SyncWorkerResult> _upload(AppDatabase db, ShopFixture f) => SyncWorker(
      queue: SyncQueueRepository(db, shopId: f.shopId),
      gateway: PsqlUploadGateway(f.ownerId),
      workerId: 'device-A',
    ).runOnce();

Future<Map<String, dynamic>> _queuedVoid(AppDatabase db, String voidId) async => jsonDecode(
      (await (db.select(db.syncOperations)..where((t) => t.entityId.equals(voidId))).getSingle()).payload,
    ) as Map<String, dynamic>;

/// Calls sync_sale_void as [actor]; returns the result JSON or 'SQLSTATE message'.
Future<String> _callVoid(String actor, Map<String, dynamic> payload) => asOwner(actor, '''
create temp table if not exists r1_out(v text) on commit drop;
do \$do\$ begin
  insert into r1_out select public.sync_sale_void(\$R1\$${jsonEncode(payload)}\$R1\$::jsonb, null)::text;
exception when others then insert into r1_out values (sqlstate || ' ' || sqlerrm);
end \$do\$;
select v from r1_out;
''');

/// Every row a void can write, for no-mutation proofs.
Future<String> _voidFootprint(String saleId) => psql('''
select (select count(*) from sale_voids where original_sale_id='$saleId') || '/' ||
  (select count(*) from inventory_movements where reference_type='sale_void') || '/' ||
  (select count(*) from customer_ledger_entries where type='refund' and sale_id='$saleId') || '/' ||
  (select count(*) from audit_logs where action='sale.voided') || '/' ||
  (select coalesce(sum(quantity),0) from inventory_movements where product_id in (select product_id from sale_items where sale_id='$saleId'));''');

Future<String> _serverIds(String sql) async => (await psql(sql)).split(',').where((s) => s.isNotEmpty).toList().join(',');

List<String> _sorted(Iterable<String> ids) => ids.toList()..sort();

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('void');
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });
  const skip = r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker';

  // Moved unchanged from the expected-red suite (F-2 fixed by R1.3).
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
    skip: skip,
  );

  test('C/D: a Cash + Digital + Udhaar void is stored with the device ids and pulls back without duplicates', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final sale = await _sell(db, f, customerId: f.customerId, payments: const [
      SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 10000),
      SalePaymentDraft(method: PaymentMethod.digital, amountMinor: 6000),
      SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 20000),
    ]);
    expect((await _upload(db, f)).synced, 1);
    final voidId = await _void(db, f, sale.saleId);
    expect((await _upload(db, f)).synced, 1);

    final localMoves = (await (db.select(db.inventoryMovements)..where((t) => t.referenceId.equals(voidId))).get());
    final localRefunds = await (db.select(db.customerLedgerEntries)..where((t) => t.type.equals('refund'))).get();
    expect(await _serverIds("select string_agg(id::text, ',' order by id) from inventory_movements where reference_id='$voidId'"),
        _sorted(localMoves.map((m) => m.id)).join(','));
    expect(await psql("select id || ':' || amount from customer_ledger_entries where type='refund' and sale_id='${sale.saleId}'"),
        '${localRefunds.single.id}:20000');
    expect(await psql("select payment_breakdown::text from sale_voids where id='$voidId'"),
        '{"cash": 10000, "credit": 20000, "digital": 6000}');

    final pull = ReferencePullService(db, PsqlPullGateway(f.ownerId), shopId: f.shopId);
    for (var i = 0; i < 3; i++) {
      await pull.pull(PullEntity.inventoryMovements);
      await pull.pull(PullEntity.customerLedgerEntries);
      await pull.pull(PullEntity.saleVoids);
    }
    expect(await (db.select(db.inventoryMovements)..where((t) => t.referenceType.equals('sale_void'))).get(), hasLength(1));
    expect(await (db.select(db.customerLedgerEntries)..where((t) => t.type.equals('refund'))).get(), hasLength(1));
    expect(await localStock(db, f.productId), ShopFixture.openingStock);
    expect(await serverScalar("select sum(quantity) from inventory_movements where product_id='${f.productId}'"),
        ShopFixture.openingStock);
    expect(await localBalance(db, f.customerId), 0);
    expect(await serverScalar("select coalesce(sum(case when type in ('openingBalance','creditSale','adjustment') "
        "then amount else -amount end),0) from customer_ledger_entries where customer_id='${f.customerId}'"), 0);
  }, skip: skip);

  test('G: the same v2 void sent concurrently (20 rounds) makes exactly one reversal', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    for (var round = 0; round < 20; round++) {
      final sale = await _sell(db, f);
      await _upload(db, f);
      final voidId = await _void(db, f, sale.saleId);
      final payload = await _queuedVoid(db, voidId);
      await (db.update(db.syncOperations)..where((t) => t.entityId.equals(voidId)))
          .write(const SyncOperationsCompanion(status: Value(SyncStatus.synced)));
      final results = await Future.wait([for (var i = 0; i < 3; i++) _callVoid(f.ownerId, payload)]);
      expect(results.where((r) => r.contains('"inserted"')), hasLength(1), reason: '$results');
      expect(results.where((r) => r.contains('"already_synced"')), hasLength(2), reason: '$results');
      expect(await psql("select count(*) from inventory_movements where reference_id='$voidId'"), '1');
      expect(await psql("select count(*) from sale_voids where original_sale_id='${sale.saleId}'"), '1');
    }
    // Two different void ids racing for one sale: only one can compensate it.
    final sale = await _sell(db, f);
    await _upload(db, f);
    final voidId = await _void(db, f, sale.saleId);
    final first = await _queuedVoid(db, voidId);
    final second = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
    (second['void'] as Map)['id'] = _uuid();
    second['audit_id'] = _uuid();
    second['movement_ids'] = {for (final key in (first['movement_ids'] as Map).keys) key: _uuid()};
    final results = await Future.wait([_callVoid(f.ownerId, first), _callVoid(f.ownerId, second)]);
    expect(results.where((r) => r.contains('"inserted"')), hasLength(1), reason: '$results');
    expect(results.where((r) => r.contains('sale already voided')), hasLength(1), reason: '$results');
    expect(await psql("select count(*) from sale_voids where original_sale_id='${sale.saleId}'"), '1');
    expect(await psql("select count(*) from inventory_movements where reference_type='sale_void' "
        "and reference_id in (select id from sale_voids where original_sale_id='${sale.saleId}')"), '1');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('H: the same void id with different content is refused without writes', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final sale = await _sell(db, f, customerId: f.customerId,
        payments: const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 36000)]);
    await _upload(db, f);
    final voidId = await _void(db, f, sale.saleId);
    expect((await _upload(db, f)).synced, 1);
    final payload = await _queuedVoid(db, voidId);
    final before = await _voidFootprint(sale.saleId);
    final changedReason = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
    (changedReason['void'] as Map)['reason'] = 'different reason';
    final changedIds = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
    changedIds['refund_ledger_id'] = _uuid();
    for (final changed in [changedReason, changedIds]) {
      expect(await _callVoid(f.ownerId, changed), contains('conflicting replay for immutable void'));
    }
    expect(await _callVoid(f.ownerId, payload), contains('"already_synced"'));
    expect(await _voidFootprint(sale.saleId), before);
  }, skip: skip);

  test('I: a legacy v1 void is refused with DPV01 before any write; the queued operation is preserved', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final sale = await _sell(db, f, customerId: f.customerId,
        payments: const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 36000)]);
    await _upload(db, f);
    final voidId = await _void(db, f, sale.saleId);
    // Exactly the pre-R1.3 queued shape: version 1, no compensation ids.
    final legacy = await _queuedVoid(db, voidId)
      ..['version'] = 1
      ..remove('movement_ids')
      ..remove('refund_ledger_id');
    final legacyText = jsonEncode(legacy);
    await (db.update(db.syncOperations)..where((t) => t.entityId.equals(voidId)))
        .write(SyncOperationsCompanion(payload: Value(legacyText)));
    final before = await _voidFootprint(sale.saleId);
    expect(await _callVoid(f.ownerId, legacy), startsWith('DPV01 '));
    for (final version in [null, 3, '2x']) {
      final other = jsonDecode(legacyText) as Map<String, dynamic>;
      if (version == null) {
        other.remove('version');
      } else {
        other['version'] = version;
      }
      expect(await _callVoid(f.ownerId, other), startsWith('DPV01 '), reason: 'version $version');
    }
    final result = await _upload(db, f);
    expect(result.synced, 0);
    final op = await (db.select(db.syncOperations)..where((t) => t.entityId.equals(voidId))).getSingle();
    expect(op.status, SyncStatus.needsAttention, reason: 'R1.5: DPV01 is permanent');
    expect(op.lastError, contains('DPV01'));
    expect(op.payload, legacyText, reason: 'never rewritten or converted');
    expect(await _voidFootprint(sale.saleId), before);
    expect(await psql("select count(*) from sale_voids where id='$voidId'"), '0');
  }, skip: skip);

  test('J: actor, tenant and forged compensation checks refuse every write', () async {
    final f = ShopFixture();
    await f.seedServer();
    final other = ShopFixture();
    await other.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final sale = await _sell(db, f, customerId: f.customerId, payments: const [
      SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 16000),
      SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 20000),
    ]);
    await _upload(db, f);
    final voidId = await _void(db, f, sale.saleId);
    final good = await _queuedVoid(db, voidId);
    final saleItemId = (good['movement_ids'] as Map).keys.single as String;
    final saleMovementId = await psql("select id from inventory_movements where reference_id='${sale.saleId}'");
    final creditEntryId = await psql("select id from customer_ledger_entries where sale_id='${sale.saleId}'");
    Map<String, dynamic> forged(void Function(Map<String, dynamic> p) change) {
      final copy = jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
      change(copy);
      return copy;
    }
    final before = await _voidFootprint(sale.saleId);
    final cases = <String, (String, Map<String, dynamic>, String)>{
      'owner of another shop': (other.ownerId, good, '42501'),
      'actor mismatch': (f.ownerId, forged((p) => (p['void'] as Map)['created_by'] = other.ownerId), '42501'),
      'sale of another shop': (other.ownerId, forged((p) => (p['void'] as Map)
        ..['shop_id'] = other.shopId
        ..['created_by'] = other.ownerId), 'original sale required'),
      'forged amount': (f.ownerId, forged((p) => (p['void'] as Map)['amount'] = 1), 'void amount mismatch'),
      'forged breakdown': (f.ownerId, forged((p) => (p['void'] as Map)['payment_breakdown'] = {'cash': 36000}), 'payment breakdown'),
      'missing compensation id': (f.ownerId, forged((p) => p['movement_ids'] = <String, String>{}), 'compensation ids'),
      'extra compensation id': (f.ownerId, forged((p) => (p['movement_ids'] as Map)[_uuid()] = _uuid()), 'compensation ids'),
      'foreign sale item key': (f.ownerId, forged((p) => p['movement_ids'] = {_uuid(): _uuid()}), 'compensation ids'),
      'refund id missing on an Udhaar sale': (f.ownerId, forged((p) => p['refund_ledger_id'] = null), 'refund ledger id'),
      'compensation id reusing the sale movement': (f.ownerId, forged((p) => p['movement_ids'] = {saleItemId: saleMovementId}), '23505'),
      'refund id reusing an existing ledger row': (f.ownerId, forged((p) => p['refund_ledger_id'] = creditEntryId), '23505'),
    };
    for (final entry in cases.entries) {
      final (actor, payload, expected) = entry.value;
      expect(await _callVoid(actor, payload), contains(expected), reason: entry.key);
      expect(await _voidFootprint(sale.saleId), before, reason: '${entry.key} wrote something');
    }
    expect(await psql("select id from inventory_movements where reference_id='${sale.saleId}'"), saleMovementId,
        reason: 'an existing movement is never overwritten');
    // The untouched payload still works afterwards.
    expect(await _callVoid(f.ownerId, good), contains('"inserted"'));
  }, skip: skip);

  test('K: the server void window compares instants (14:59 accepted, 15:01 refused)', () async {
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    final soldAt = DateTime.utc(2026, 9, 30, 5);
    Future<String> voidAfter(Duration after) async {
      final sale = await _sell(db, f, at: soldAt);
      await _upload(db, f);
      final voidId = await _void(db, f, sale.saleId, at: soldAt.add(const Duration(minutes: 1)));
      final payload = await _queuedVoid(db, voidId);
      await (db.update(db.syncOperations)..where((t) => t.entityId.equals(voidId)))
          .write(const SyncOperationsCompanion(status: Value(SyncStatus.synced)));
      (payload['void'] as Map)['created_at'] = soldAt.add(after).toIso8601String();
      return _callVoid(f.ownerId, payload);
    }

    expect(await voidAfter(const Duration(minutes: 14, seconds: 59)), contains('"inserted"'));
    expect(await voidAfter(const Duration(minutes: 15, seconds: 1)), contains('void correction window expired'));
    expect(await voidAfter(const Duration(seconds: -1)), contains('void correction window expired'));
  }, skip: skip);

  test('L: an offline void survives a restart with the same void and compensation ids', () async {
    final f = ShopFixture();
    await f.seedServer();
    final dir = Directory.systemTemp.createTempSync('r1_3_restart_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}device.sqlite');
    final db = await f.openDevice(file: file);
    final sale = await _sell(db, f, customerId: f.customerId,
        payments: const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 36000)]);
    await _upload(db, f);
    final voidId = await _void(db, f, sale.saleId); // offline: not uploaded
    final queued = (await (db.select(db.syncOperations)..where((t) => t.entityId.equals(voidId))).getSingle()).payload;
    final localMoveIds = (await (db.select(db.inventoryMovements)..where((t) => t.referenceId.equals(voidId))).get())
        .map((m) => m.id)
        .toList();
    await db.close();

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final op = await (reopened.select(reopened.syncOperations)..where((t) => t.entityId.equals(voidId))).getSingle();
    expect(op.payload, queued);
    expect((await _upload(reopened, f)).synced, 1);
    expect(await psql("select id from inventory_movements where reference_id='$voidId'"), localMoveIds.single);
    final refund = await (reopened.select(reopened.customerLedgerEntries)..where((t) => t.type.equals('refund'))).getSingle();
    expect(await psql("select id from customer_ledger_entries where type='refund' and sale_id='${sale.saleId}'"), refund.id);
    expect(await psql("select count(*) from sale_voids where id='$voidId'"), '1');
  }, skip: skip);
}
