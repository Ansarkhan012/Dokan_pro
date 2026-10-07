// R1.5 server contract (migration 202610020001): stable SQLSTATEs for sale,
// customer payment, void and return rejections, proven through the real
// worker into the outbox state; record-and-flag for the credit limit (exactly
// one copy of every financial row), the flag policy confined to the sync RPC,
// owner-only visibility of flags, and an upgrade over existing synced data.
@Tags(['r1-direct-db'])
library;

import 'dart:convert';
import 'dart:io';


import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/local_customer_payment_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/direct_db_server.dart';

Future<Map<String, dynamic>> _queuedSale(
  AppDatabase db,
  ShopFixture f, {
  bool credit = false,
  String? device,
}) async {
  final sale = await LocalSaleService(db, const UuidV7Generator()).createSale(SaleDraft(
    shopId: f.shopId,
    cashierId: f.ownerId,
    deviceId: device ?? f.deviceA,
    customerId: credit ? f.customerId : null,
    lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
    payments: [
      SalePaymentDraft(
        method: credit ? PaymentMethod.credit : PaymentMethod.cash,
        amountMinor: ShopFixture.salePrice,
      ),
    ],
  ));
  final op = await (db.select(db.syncOperations)..where((t) => t.entityId.equals(sale.saleId))).getSingle();
  return jsonDecode(op.payload) as Map<String, dynamic>;
}

/// `OK <status>[ flags]` or the SQLSTATE the RPC raised.
Future<String> _call(String owner, Map<String, dynamic> payload) async {
  try {
    final result = await PsqlUploadGateway(owner).uploadSaleAggregate(payload) as Map;
    final flags = result['flags'] as List?;
    return 'OK ${result['status']}${flags == null ? '' : ' $flags'}';
  } on ServerRejected catch (e) {
    return e.code ?? 'no code: ${e.message}';
  }
}

Map<String, dynamic> _copy(Map<String, dynamic> payload) =>
    jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

Future<String> _serverFootprint(ShopFixture f) => psql('''
select (select count(*) from sales where shop_id='${f.shopId}') || '/' ||
  (select count(*) from sale_items where shop_id='${f.shopId}') || '/' ||
  (select count(*) from sale_payments where shop_id='${f.shopId}') || '/' ||
  (select count(*) from inventory_movements where shop_id='${f.shopId}' and type='sale') || '/' ||
  (select count(*) from customer_ledger_entries where shop_id='${f.shopId}') || '/' ||
  (select count(*) from sync_exceptions where shop_id='${f.shopId}');
''');

String _id() => const Uuid().v4();

/// Runs the real worker [runs] times through the real RPC, jumping the clock
/// past every backoff, and returns the uploads it attempted.
Future<List<String>> _drain(AppDatabase db, ShopFixture f, {int runs = 3}) async {
  final gateway = PsqlUploadGateway(f.ownerId);
  var clock = DateTime.now().toUtc();
  for (var i = 0; i < runs; i++) {
    await SyncWorker(
      queue: SyncQueueRepository(db, shopId: f.shopId),
      gateway: gateway,
      workerId: 'device-A',
      clock: () => clock,
    ).runOnce(limit: 50);
    clock = clock.add(const Duration(minutes: 6));
  }
  return gateway.calls;
}

/// Queues a hand-crafted operation exactly as the local services do.
Future<void> _enqueue(AppDatabase db, ShopFixture f, String type, String entityId, Map<String, dynamic> payload) async {
  final now = DateTime.now().toUtc();
  await db.into(db.syncOperations).insert(SyncOperationsCompanion.insert(
    id: _id(), shopId: f.shopId, deviceId: f.deviceA, entityType: type, entityId: entityId,
    operationType: SyncOperationType.create, payload: jsonEncode(payload), createdAt: now, updatedAt: now,
  ));
}

Future<SyncOperation> _opFor(AppDatabase db, String entityId, {String? payloadContains}) async {
  final ops = await (db.select(db.syncOperations)..where((t) => t.entityId.equals(entityId))).get();
  return ops.lastWhere((o) => payloadContains == null || o.payload.contains(payloadContains));
}

Future<Map<String, dynamic>> _payloadOf(AppDatabase db, String entityId) async =>
    jsonDecode((await _opFor(db, entityId)).payload) as Map<String, dynamic>;

/// Messages the stable-code mapper translates (single-quoted literals with a
/// space in r1_raise_stable_sync_error, minus the `'<CODE>: '` prefixes).
List<String> _mappedMessages() {
  final sql = File('supabase/migrations/202610020001_r1_sync_codes_and_flags.sql').readAsStringSync();
  final start = sql.indexOf('create function public.r1_raise_stable_sync_error');
  final body = sql.substring(start, sql.indexOf(r'end $$;', start));
  return [
    for (final m in RegExp(r"'([^']+)'").allMatches(body))
      if (m.group(1)!.contains(' ') && !m.group(1)!.endsWith(': ')) m.group(1)!,
  ];
}

void main() {
  test('every message the code mapper translates is raised by migrations 1-20', () {
    final earlier = migrationFiles()
        .where((f) => !f.path.endsWith('202610020001_r1_sync_codes_and_flags.sql'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    final messages = _mappedMessages();
    expect(messages.length, greaterThanOrEqualTo(30));
    for (final message in messages) {
      expect(earlier.contains("raise exception '$message'"), isTrue,
          reason: 'mapped message "$message" is no longer raised; its stable code would be lost');
    }
  });

  group('sync codes', () {
    setUpAll(() async {
      if (r1ServerEnabled) await createScratchServer('sync_codes');
    });
    tearDownAll(() async {
      if (r1ServerEnabled) await dropScratchServer();
    });

    test('validation rejections are DPV01 and write nothing', () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      final good = await _queuedSale(db, f);
      final zero = _copy(good)..['payments'][0]['amount'] = 0;
      final total = _copy(good)..['sale']['grandTotal'] = 1;
      final version = _copy(good)..['version'] = 9;
      final badId = _copy(good)..['sale']['id'] = 'not-a-uuid';
      final badNumber = _copy(good)..['sale_items'][0]['quantity'] = 'many';
      for (final (name, payload) in [
        ('zero-amount payment', zero),
        ('header total', total),
        ('payload version', version),
        ('sale id', badId),
        ('malformed number', badNumber),
      ]) {
        expect(await _call(f.ownerId, payload), 'DPV01', reason: name);
      }
      expect(await _serverFootprint(f), '0/0/0/0/0/0');
      expect(await _call(f.ownerId, good), 'OK inserted');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('a conflicting replay is DPC01; an identical replay is already_synced', () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      final sale = await _queuedSale(db, f);
      expect(await _call(f.ownerId, sale), 'OK inserted');
      expect(await _call(f.ownerId, sale), 'OK already_synced');
      final changed = _copy(sale)..['sale']['invoiceNumber'] = 'CHANGED';
      expect(await _call(f.ownerId, changed), 'DPC01');
      expect(await _serverFootprint(f), '1/1/1/1/0/0');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('an inactive device or foreign cashier is DPA01; a foreign owner keeps 42501', () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      final fromB = await _queuedSale(db, f, device: f.deviceB);
      await psql("update devices set is_active=false where id='${f.deviceB}'");
      expect(await _call(f.ownerId, fromB), 'DPA01');
      final foreignCashier = _copy(await _queuedSale(db, f))..['sale']['cashierId'] = const Uuid().v4();
      expect(await _call(f.ownerId, foreignCashier), 'DPA01');
      final other = ShopFixture();
      await other.seedServer();
      expect(await _call(other.ownerId, await _queuedSale(db, f)), '42501');
      expect(await _serverFootprint(f), '0/0/0/0/0/0');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('other rejections keep their own SQLSTATE (bounded unknown on the device)', () async {
      final f = ShopFixture();
      await f.seedServer(creditLimit: 100000);
      final db = await f.openDevice(creditLimit: 100000);
      addTearDown(db.close);
      final credit = await _queuedSale(db, f, credit: true);
      await psql("update customers set is_active=false where id='${f.customerId}'");
      expect(await _call(f.ownerId, credit), 'P0001');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('credit limit exceeded offline is recorded once and flagged; a replay adds nothing', () async {
      final f = ShopFixture();
      await f.seedServer(creditLimit: 30000);
      final a = await f.openDevice(creditLimit: 30000);
      final b = await f.openDevice(creditLimit: 30000);
      addTearDown(a.close);
      addTearDown(b.close);
      final saleA = await _queuedSale(a, f, credit: true);
      final saleB = await _queuedSale(b, f, credit: true, device: f.deviceB);
      expect(await _call(f.ownerId, saleA), 'OK inserted');
      final queueB = SyncQueueRepository(b, shopId: f.shopId);
      final result = await SyncWorker(queue: queueB, gateway: PsqlUploadGateway(f.ownerId), workerId: 'b').runOnce();
      expect(result.synced, 1);
      expect(await _serverFootprint(f), '2/2/2/2/2/1');
      final saleBId = saleB['sale']['id'];
      expect(await psql("select rule_code || ' ' || (detail->>'credit_limit') || ' ' || (detail->>'balance_before') "
          "from sync_exceptions where entity_id='$saleBId'"), 'credit_limit_exceeded 30000 18000');
      expect(await psql("select coalesce(sum(amount),0) from customer_ledger_entries where customer_id='${f.customerId}'"),
          '36000', reason: 'the real Udhaar is kept, not rolled back');
      final op = (await queueB.attention()).single;
      expect((op.status, op.errorClass, op.errorCode), (SyncStatus.synced, 'flagged', 'credit_limit_exceeded'));

      expect(await _call(f.ownerId, saleB), 'OK already_synced [credit_limit_exceeded]');
      expect(await _serverFootprint(f), '2/2/2/2/2/1', reason: 'no duplicate sale, stock, payment, Udhaar or flag');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('record-and-flag applies only inside the sale sync RPC', () async {
      final f = ShopFixture();
      await f.seedServer(creditLimit: 10000);
      // Any path other than sync_sale_transaction (here a direct insert)
      // still raises; nothing is flagged.
      await expectLater(
        psql("insert into customer_ledger_entries(id,shop_id,customer_id,type,amount,created_by,created_at) "
            "values(gen_random_uuid(),'${f.shopId}','${f.customerId}','creditSale',20000,'${f.ownerId}',now());"),
        throwsA(isA<ServerRejected>().having((e) => e.message, 'message', contains('customer credit limit exceeded'))),
      );
      expect(await psql("select count(*) from customer_ledger_entries where customer_id='${f.customerId}'"), '0');
      expect(await psql("select count(*) from sync_exceptions where shop_id='${f.shopId}'"), '0');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('only the shop owner can read its sync flags', () async {
      final f = ShopFixture();
      await f.seedServer(creditLimit: 0);
      final db = await f.openDevice(); // offline: has not seen the limit yet
      addTearDown(db.close);
      expect(await _call(f.ownerId, await _queuedSale(db, f, credit: true)), 'OK accepted_flagged [credit_limit_exceeded]');
      final other = ShopFixture();
      await other.seedServer();
      Future<String> visible(String owner) => asOwner(owner, 'select count(*) from public.sync_exceptions;');
      expect(await visible(f.ownerId), '1');
      expect(await visible(other.ownerId), '0');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');
  });

  group('payment, void and return codes through the worker', () {
    setUpAll(() async {
      if (r1ServerEnabled) await createScratchServer('sync_codes_ops');
    });
    tearDownAll(() async {
      if (r1ServerEnabled) await dropScratchServer();
    });

    test('customer payment: DPC01 / DPV01 need attention after one upload; a revoked device is DPA01 blockedAuth', () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      await _queuedSale(db, f, credit: true); // Udhaar 18000 to pay against
      // receive() returns the outbox operation id; the entity is the ledger entry.
      Future<String> pay(int amount) async {
        final operationId = await LocalCustomerPaymentService(db, const UuidV7Generator()).receive(
          shopId: f.shopId, customerId: f.customerId, actorId: f.ownerId, deviceId: f.deviceA,
          amountMinor: amount, method: PaymentMethod.cash,
        );
        return (await (db.select(db.syncOperations)..where((t) => t.id.equals(operationId))).getSingle()).entityId;
      }
      final paid = await pay(5000);
      await _drain(db, f, runs: 1);
      expect((await _opFor(db, paid)).status, SyncStatus.synced);

      final conflict = (await _payloadOf(db, paid))..['entry']['note'] = 'changed after sync';
      await _enqueue(db, f, 'customer_payment', paid, conflict);
      final invalidId = _id();
      final invalid = jsonDecode(jsonEncode(conflict)) as Map<String, dynamic>;
      invalid['entry']['id'] = invalidId;
      invalid['entry']['amount'] = 0;
      invalid['audit']['id'] = _id();
      await _enqueue(db, f, 'customer_payment', invalidId, invalid);
      final calls = await _drain(db, f);
      expect(calls.where((c) => c.contains('ERR DPC01')), hasLength(1), reason: '$calls');
      expect(calls.where((c) => c.contains('ERR DPV01')), hasLength(1), reason: 'never retried: $calls');
      final conflictOp = await _opFor(db, paid, payloadContains: 'changed after sync');
      expect((conflictOp.status, conflictOp.errorCode), (SyncStatus.needsAttention, 'DPC01'));
      final invalidOp = await _opFor(db, invalidId);
      expect((invalidOp.status, invalidOp.errorCode), (SyncStatus.needsAttention, 'DPV01'));

      await psql("update devices set is_active=false where id='${f.deviceA}'");
      final blocked = await pay(1000);
      final afterRevoke = await _drain(db, f);
      expect(afterRevoke.where((c) => c.contains('ERR DPA01')), hasLength(1), reason: '$afterRevoke');
      final blockedOp = await _opFor(db, blocked);
      expect((blockedOp.status, blockedOp.errorCode), (SyncStatus.blockedAuth, 'DPA01'));
      expect(await psql("select count(*) from customer_ledger_entries where customer_id='${f.customerId}'"), '2',
          reason: 'one credit sale and one payment; nothing rejected was written');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('void: a second void is DPX01, a forged amount DPV01, a changed replay DPC01 — each needs attention at once', () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      final first = (await _queuedSale(db, f))['sale']['id'] as String;
      final second = (await _queuedSale(db, f))['sale']['id'] as String;
      await _drain(db, f, runs: 1);
      final voidId = await LocalSaleVoidService(db, const UuidV7Generator()).voidSale(
          shopId: f.shopId, saleId: first, ownerId: f.ownerId, deviceId: f.deviceA, reason: 'wrong item');
      await _drain(db, f, runs: 1);
      expect((await _opFor(db, voidId)).status, SyncStatus.synced);
      final applied = await _payloadOf(db, voidId);

      Map<String, dynamic> copy() => jsonDecode(jsonEncode(applied)) as Map<String, dynamic>;
      final again = copy();
      final againId = _id();
      again['void']['id'] = againId;
      again['movement_ids'] = {for (final k in (applied['movement_ids'] as Map).keys) k: _id()};
      again['audit_id'] = _id();
      await _enqueue(db, f, 'sale_void', againId, again);
      final changed = copy()..['void']['reason'] = 'changed after sync';
      await _enqueue(db, f, 'sale_void', voidId, changed);
      final forgedId = _id();
      final forged = copy();
      forged['void']['id'] = forgedId;
      forged['void']['original_sale_id'] = second;
      forged['void']['amount'] = 1;
      forged['audit_id'] = _id();
      await _enqueue(db, f, 'sale_void', forgedId, forged);

      final calls = await _drain(db, f);
      for (final code in ['DPX01', 'DPC01', 'DPV01']) {
        expect(calls.where((c) => c.contains('ERR $code')), hasLength(1), reason: '$code once, never retried: $calls');
      }
      expect(((await _opFor(db, againId)).status, (await _opFor(db, againId)).errorCode),
          (SyncStatus.needsAttention, 'DPX01'));
      final changedOp = await _opFor(db, voidId, payloadContains: 'changed after sync');
      expect((changedOp.status, changedOp.errorCode), (SyncStatus.needsAttention, 'DPC01'));
      expect(((await _opFor(db, forgedId)).status, (await _opFor(db, forgedId)).errorCode),
          (SyncStatus.needsAttention, 'DPV01'));
      expect(await psql("select count(*) from sale_voids where shop_id='${f.shopId}'"), '1');
      expect(await psql("select count(*) from inventory_movements where reference_type='sale_void' and shop_id='${f.shopId}'"), '1');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('return: beyond the sold quantity is DPX01 and needs attention at once', () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      final saleId = (await _queuedSale(db, f))['sale']['id'] as String;
      await _drain(db, f, runs: 1);
      final item = await (db.select(db.saleItems)..where((t) => t.saleId.equals(saleId))).getSingle();
      final created = await LocalSaleReturnService(db, const UuidV7Generator()).create(SaleReturnDraft(
        shopId: f.shopId, originalSaleId: saleId, ownerId: f.ownerId, deviceId: f.deviceA,
        refundMethod: PaymentMethod.cash, reason: 'damaged',
        lines: [SaleReturnLineDraft(originalSaleItemId: item.id, quantity: 1000)],
      ));
      await _drain(db, f, runs: 1);
      expect((await _opFor(db, created.returnId)).status, SyncStatus.synced);

      final again = jsonDecode(jsonEncode(await _payloadOf(db, created.returnId))) as Map<String, dynamic>;
      final againId = _id();
      again['return']['id'] = againId;
      for (final row in [...again['items'] as List, ...again['inventory_movements'] as List]) {
        (row as Map)['id'] = _id();
      }
      again['audit_id'] = _id();
      await _enqueue(db, f, 'sale_return', againId, again);
      final calls = await _drain(db, f);
      expect(calls.where((c) => c.contains('ERR DPX01')), hasLength(1), reason: 'once, never retried: $calls');
      final op = await _opFor(db, againId);
      expect((op.status, op.errorCode), (SyncStatus.needsAttention, 'DPX01'));
      expect(op.lastError, contains('return exceeds sold quantity'));
      expect(await psql("select count(*) from sale_returns where shop_id='${f.shopId}'"), '1');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');

    test('transient and unmapped errors keep their own SQLSTATE through every wrapper', () async {
      final f = ShopFixture();
      await f.seedServer();
      Future<String> raw(String rpc, Map<String, dynamic> payload) => asOwner(f.ownerId, '''
create temp table if not exists r1_raw(v text) on commit drop;
do \$do\$ begin
  insert into r1_raw select public.$rpc(\$R1\$${jsonEncode(payload)}\$R1\$::jsonb, null)::text;
exception when others then insert into r1_raw values (sqlstate);
end \$do\$;
select v from r1_raw;
''');
      // An unknown original sale is not a mapped rejection: it keeps P0001.
      expect(await raw('sync_sale_return', {
        'version': 1, 'operation': 'sync_sale_return',
        'return': {'id': _id(), 'shop_id': f.shopId, 'original_sale_id': _id(), 'device_id': f.deviceA,
          'refund_method': 'cash', 'refund_amount': 100, 'reason': 'x', 'created_by': f.ownerId,
          'created_at': DateTime.now().toUtc().toIso8601String()},
        'items': [{'id': _id()}], 'inventory_movements': [], 'ledger_id': null, 'audit_id': _id(),
      }), 'P0001');
      // A caller who is not the owner keeps 42501 (auth), not a DP code.
      final other = ShopFixture();
      await other.seedServer();
      expect(await asOwner(other.ownerId, '''
create temp table if not exists r1_raw(v text) on commit drop;
do \$do\$ begin
  insert into r1_raw select public.sync_sale_void(\$R1\$${jsonEncode({'version': 2, 'void': {'id': _id(), 'shop_id': f.shopId, 'created_by': other.ownerId}})}\$R1\$::jsonb, null)::text;
exception when others then insert into r1_raw values (sqlstate);
end \$do\$;
select v from r1_raw;
'''), '42501');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');
  });

  group('upgrade from the R1.4 schema', () {
    setUpAll(() async {
      if (r1ServerEnabled) await createScratchServer('sync_codes_upgrade', 20);
    });
    tearDownAll(() async {
      if (r1ServerEnabled) await dropScratchServer();
    });

    test('existing synced sales keep replaying as already_synced; new sales get codes and flags', () async {
      final f = ShopFixture();
      await f.seedServer(creditLimit: 30000);
      final db = await f.openDevice(); // offline: has not seen the limit yet
      addTearDown(db.close);
      final before = await _queuedSale(db, f, credit: true);
      expect(await _call(f.ownerId, before), 'OK inserted');
      final hash = await psql("select encode(aggregate_hash,'hex') from sales where id='${before['sale']['id']}'");

      final migration = migrationFiles()[20];
      expect(migration.path, endsWith('202610020001_r1_sync_codes_and_flags.sql'));
      await psql(migration.readAsStringSync());

      expect(await _call(f.ownerId, before), 'OK already_synced');
      expect(await psql("select encode(aggregate_hash,'hex') from sales where id='${before['sale']['id']}'"), hash);
      expect(await _call(f.ownerId, await _queuedSale(db, f, credit: true)),
          'OK accepted_flagged [credit_limit_exceeded]');
      expect(await _call(f.ownerId, _copy(await _queuedSale(db, f))..['payments'][0]['amount'] = 0), 'DPV01');
      expect(await _serverFootprint(f), '2/2/2/2/2/1');
    }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');
  });
}
