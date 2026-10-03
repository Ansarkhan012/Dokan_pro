// R1.5 + R1.6 contract (design §H/§I): transient failures retry, permanent
// ones need attention and are never retried automatically, unknown ones are
// bounded, auth failures wait for a new session, server flags keep the sale
// exactly once and stay visible, and no worker or lease failure escapes or
// poisons later runs. Pure local: no Docker, no network.
@Tags(['r1-green'])
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_failure.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../support/pos_fixture.dart';

PostgrestException _server(String code, [String message = 'rejected']) =>
    PostgrestException(message: message, code: code);

/// Answers each upload with the next scripted response: an exception to
/// throw, or a value to return as the RPC result. The last one repeats.
final class _Gateway implements SaleUploadGateway {
  _Gateway(this.script);
  final List<Object?> script;
  final payloads = <Map<String, dynamic>>[];
  Future<void> Function()? onUpload;

  @override
  Future<Object?> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) async {
    payloads.add(payload);
    await onUpload?.call();
    final next = script[(payloads.length - 1).clamp(0, script.length - 1)];
    if (next is Exception || next is Error) throw next!;
    return next ?? {'status': 'inserted'};
  }
}

const _accepted = {'status': 'inserted'};
const _flagged = {
  'status': 'accepted_flagged',
  'flags': ['credit_limit_exceeded'],
};

Future<AppDatabase> _device([File? file]) async {
  final db = AppDatabase(file == null ? NativeDatabase.memory() : NativeDatabase(file));
  await seed(db);
  return db;
}

Future<String> _sell(AppDatabase db, {bool udhaar = false}) async =>
    (await LocalSaleService(db, const UuidV7Generator()).createSale(SaleDraft(
      shopId: shopId,
      cashierId: ownerId,
      deviceId: deviceId,
      customerId: udhaar ? customerId : null,
      lines: const [SaleLineDraft(productId: cokeId, quantity: 1000)],
      payments: [
        SalePaymentDraft(
          method: udhaar ? PaymentMethod.credit : PaymentMethod.cash,
          amountMinor: cokePrice,
        ),
      ],
    ))).saleId;

/// Runs the real worker [runs] times, jumping the clock past every backoff.
Future<DateTime> _runs(
  AppDatabase db,
  SaleUploadGateway gateway,
  int runs, {
  DateTime? from,
  Duration step = const Duration(minutes: 6),
  String workerId = 'device-worker',
}) async {
  var clock = from ?? DateTime.utc(2026, 10, 2, 9);
  for (var i = 0; i < runs; i++) {
    await SyncWorker(
      queue: SyncQueueRepository(db, shopId: shopId),
      gateway: gateway,
      workerId: workerId,
      clock: () => clock,
    ).runOnce();
    clock = clock.add(step);
  }
  return clock;
}

Future<SyncOperation> _op(AppDatabase db, String entityId) =>
    (db.select(db.syncOperations)..where((t) => t.entityId.equals(entityId))).getSingle();

Future<bool> _eligibleAfter30Days(AppDatabase db, DateTime clock) async =>
    await SyncQueueRepository(db, shopId: shopId).acquireLease(
      workerId: 'probe',
      now: clock.add(const Duration(days: 30)),
    ) !=
    null;

/// Every financial row a sale writes, for no-mutation / no-duplicate proofs.
Future<String> _ledger(AppDatabase db) async {
  final out = StringBuffer();
  for (final table in const [
    'sales', 'sale_items', 'sale_payments', 'inventory_movements',
    'customer_ledger_entries', 'audit_logs',
  ]) {
    final rows = await db.customSelect('select * from $table order by id').get();
    out.writeln('$table: ${rows.map((r) => r.data).toList()}');
  }
  return out.toString();
}

void main() {
  group('R1.5 classification', () {
    test('stable codes and transport types classify deterministically; message text never decides', () {
      SyncFailureKind kind(Object error) => classifySyncError(error).kind;
      for (final code in ['DPV01', 'DPC01', 'DPX01']) {
        expect(kind(_server(code)), SyncFailureKind.permanent, reason: code);
        expect(classifySyncError(_server(code)).code, code);
      }
      for (final code in ['DPA01', '42501', 'PGRST301', '401', '403']) {
        expect(kind(_server(code)), SyncFailureKind.auth, reason: code);
      }
      for (final code in ['500', '502', '503', '504', '408', '429', '40001', '40P01', '55P03', '57014', '08006', '53300', '57P01']) {
        expect(kind(_server(code)), SyncFailureKind.transient, reason: code);
      }
      for (final error in <Object>[
        const SocketException('offline'),
        TimeoutException('slow'),
        http.ClientException('connection reset'),
        const HttpException('closed'),
      ]) {
        expect(kind(error), SyncFailureKind.connectivity, reason: '$error');
      }
      expect(kind(const AmbiguousTimestampPayload('sale.createdAt', '2026-09-30T10:00:00')),
          SyncFailureKind.permanent);
      // A message that merely mentions a code is not a code.
      expect(kind(_server('P0001', 'DPV01: looks permanent')), SyncFailureKind.unknown);
      expect(kind(_server('23514', 'customer credit limit exceeded')), SyncFailureKind.unknown);
      expect(kind(StateError('anything')), SyncFailureKind.unknown);
      for (final code in ['DPV01', 'DPA01', '503']) {
        final reason = classifySyncError(_server(code, 'select * from secret_table')).reason;
        expect(reason, isNot(contains('secret_table')), reason: 'owner reason is never server text');
      }
    });
  });

  group('R1.5 failure states', () {
    test('connectivity and transient server failures keep retrying and never need attention', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db);
      final gateway = _Gateway([
        for (var i = 0; i < 6; i++) const SocketException('offline'),
        TimeoutException('no answer'),
        _server('503'),
        _server('40001'),
        _accepted,
      ]);
      var clock = DateTime.utc(2026, 10, 2, 9);
      for (var attempt = 1; attempt <= 9; attempt++) {
        clock = await _runs(db, gateway, 1, from: clock);
        final op = await _op(db, sale);
        expect(op.status, SyncStatus.failed, reason: 'attempt $attempt is retry-wait');
        expect(op.retryCount, attempt);
        expect(op.nextAttemptAt, isNotNull);
      }
      expect((await _op(db, sale)).errorClass, SyncFailureKind.transient.name);
      await _runs(db, gateway, 1, from: clock);
      final op = await _op(db, sale);
      expect(op.status, SyncStatus.synced);
      expect((op.errorClass, op.errorCode, op.attentionReason), (null, null, null));
      expect(gateway.payloads, hasLength(10));
    });

    test('a permanent rejection needs attention immediately and is never retried automatically', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db);
      final payload = (await _op(db, sale)).payload;
      final before = await _ledger(db);
      final gateway = _Gateway([_server('DPV01', 'DPV01: invalid sale payment')]);
      final clock = await _runs(db, gateway, 12);
      expect(gateway.payloads, hasLength(1), reason: 'not retried every sync cycle');
      final op = await _op(db, sale);
      expect(op.status, SyncStatus.needsAttention);
      expect(op.errorClass, SyncFailureKind.permanent.name);
      expect(op.errorCode, 'DPV01');
      expect(op.attentionReason, 'The cloud rejected this record as invalid or out of date.');
      expect(op.attentionAt, isNotNull);
      expect(op.lastError, contains('invalid sale payment'), reason: 'technical detail kept for diagnosis');
      expect(op.payload, payload, reason: 'the original operation is kept unchanged');
      expect(await _ledger(db), before, reason: 'the local sale is never rolled back');
      expect(await _eligibleAfter30Days(db, clock), isFalse);
    });

    test('an unknown error retries a bounded number of times, then needs attention', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db);
      final gateway = _Gateway([_server('P0001', 'active customer required')]);
      final clock = await _runs(db, gateway, 10);
      expect(gateway.payloads, hasLength(SyncQueueRepository.maxUnknownErrors));
      final op = await _op(db, sale);
      expect(op.status, SyncStatus.needsAttention);
      expect((op.errorClass, op.errorCode), (SyncFailureKind.unknown.name, 'P0001'));
      expect(op.unknownErrorCount, SyncQueueRepository.maxUnknownErrors);
      expect(await _eligibleAfter30Days(db, clock), isFalse);

      // ...or after one hour since the first unknown error, whichever is first.
      final slow = await _sell(db);
      final start = DateTime.utc(2026, 10, 3, 9);
      final second = _Gateway([StateError('unexpected')]);
      await _runs(db, second, 1, from: start);
      expect((await _op(db, slow)).status, SyncStatus.failed);
      await _runs(db, second, 1, from: start.add(const Duration(minutes: 61)));
      expect((await _op(db, slow)).status, SyncStatus.needsAttention);
      expect(second.payloads, hasLength(2));
    });

    test('DPA01 blocks on authorisation without timer retries; a new session resumes it', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db);
      final gateway = _Gateway([_server('DPA01', 'DPA01: inactive or foreign device'), _accepted]);
      final clock = await _runs(db, gateway, 6);
      expect(gateway.payloads, hasLength(1));
      expect((await _op(db, sale)).status, SyncStatus.blockedAuth);
      expect(await _eligibleAfter30Days(db, clock), isFalse);
      expect(syncHealthOf(await db.select(db.syncOperations).get()), SyncHealth.needsAttention);

      expect(await SyncQueueRepository(db, shopId: shopId).resumeBlockedAuth(clock), 1);
      await _runs(db, gateway, 1, from: clock);
      expect((await _op(db, sale)).status, SyncStatus.synced);
      expect(gateway.payloads, hasLength(2));
    });

    test('owner Retry re-queues the unchanged payload; nothing is deleted', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db);
      final payload = (await _op(db, sale)).payload;
      final gateway = _Gateway([_server('DPC01'), _accepted]);
      final clock = await _runs(db, gateway, 3);
      final queue = SyncQueueRepository(db, shopId: shopId);
      expect((await queue.attention()).map((o) => o.entityId), [sale]);
      await queue.retryAttention((await _op(db, sale)).id, clock);
      final requeued = await _op(db, sale);
      expect((requeued.status, requeued.retryCount, requeued.errorCode), (SyncStatus.pending, 0, null));
      expect(requeued.payload, payload);
      await _runs(db, gateway, 1, from: clock);
      expect((await _op(db, sale)).status, SyncStatus.synced);
      expect(gateway.payloads.last, gateway.payloads.first, reason: 'same payload sent again');
      expect(await db.select(db.sales).get(), hasLength(1));
    });

    test('a dependant of a needs-attention operation needs attention instead of waiting forever', () async {
      final db = await _device();
      addTearDown(db.close);
      final parentSale = await _sell(db);
      final parent = await _op(db, parentSale);
      final t = DateTime.utc(2026, 10, 2);
      await db.into(db.syncOperations).insert(SyncOperationsCompanion.insert(
        id: 'child-op', shopId: shopId, deviceId: deviceId, entityType: 'sale_void',
        entityId: 'void-1', operationType: SyncOperationType.create, payload: '{}',
        dependsOnOperationId: Value(parent.id), createdAt: t, updatedAt: t,
      ));
      final gateway = _Gateway([_server('DPV01')]);
      await _runs(db, gateway, 3);
      expect(gateway.payloads, hasLength(1), reason: 'only the parent was ever sent');
      final child = await _op(db, 'void-1');
      expect((child.status, child.errorCode), (SyncStatus.needsAttention, 'parent_needs_attention'));

      // Owner Retry of the parent queues the dependant again with it.
      await SyncQueueRepository(db, shopId: shopId).retryAttention(parent.id, t);
      expect((await _op(db, 'void-1')).status, SyncStatus.pending);
    });
  });

  group('R1.5 accepted offline, flagged by the cloud', () {
    test('accepted_flagged keeps the offline sale and its Udhaar exactly once and flags it for the owner', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db, udhaar: true);
      final before = await _ledger(db);
      final queue = SyncQueueRepository(db, shopId: shopId);
      final gateway = _Gateway([_flagged]);
      final clock = await _runs(db, gateway, 4);
      expect(gateway.payloads, hasLength(1));
      final op = await _op(db, sale);
      expect(op.status, SyncStatus.synced, reason: 'recorded in the cloud, never retried');
      expect((op.errorClass, op.errorCode), ('flagged', 'credit_limit_exceeded'));
      expect(op.attentionReason, contains('customer credit limit exceeded'));
      expect(await _ledger(db), before, reason: 'no rollback and no duplicate sale, stock, payment or Udhaar');
      expect(await db.select(db.customerLedgerEntries).get(), hasLength(1));
      expect(await queue.attention(), hasLength(1));
      expect(syncHealthOf(await db.select(db.syncOperations).get()), SyncHealth.needsAttention);

      await queue.acknowledgeFlag(op.id, clock);
      expect(await queue.attention(), isEmpty);
      expect(syncHealthOf(await db.select(db.syncOperations).get()), SyncHealth.synced);
      expect((await _op(db, sale)).errorCode, 'credit_limit_exceeded', reason: 'the flag stays on record');
    });

    test('a replay that answers already_synced with flags is flagged too', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db, udhaar: true);
      await _runs(db, _Gateway([{'status': 'already_synced', 'flags': ['credit_limit_exceeded']}]), 1);
      final op = await _op(db, sale);
      expect((op.status, op.errorClass), (SyncStatus.synced, 'flagged'));
    });
  });

  group('R1.6 worker containment', () {
    test('one failed operation does not stop the others in the same run', () async {
      final db = await _device();
      addTearDown(db.close);
      final first = await _sell(db);
      final second = await _sell(db);
      final gateway = _Gateway([_server('DPV01'), _accepted]);
      final result = await SyncWorker(
        queue: SyncQueueRepository(db, shopId: shopId),
        gateway: gateway,
        workerId: 'device-worker',
      ).runOnce();
      expect((result.synced, result.failed), (1, 1));
      expect((await _op(db, first)).status, SyncStatus.needsAttention);
      expect((await _op(db, second)).status, SyncStatus.synced);
    });

    test('a lost lease is contained: the new owner completes it once and nothing is duplicated', () async {
      final db = await _device();
      addTearDown(db.close);
      final sale = await _sell(db);
      final before = await _ledger(db);
      final gateway = _Gateway([_accepted, {'status': 'already_synced'}]);
      gateway.onUpload = () async {
        if (gateway.payloads.length == 1) {
          await db.customStatement("update sync_operations set lease_owner='worker-b'");
        }
      };
      final queue = SyncQueueRepository(db, shopId: shopId);
      final t = DateTime.utc(2026, 10, 2, 9);
      final a = await SyncWorker(queue: queue, gateway: gateway, workerId: 'worker-a', clock: () => t).runOnce();
      expect((a.synced, a.leaseLost), (0, 1), reason: 'A no longer owns it and writes nothing');
      expect((await _op(db, sale)).leaseOwner, 'worker-b');
      // The new owner proceeds once the lease it holds expires (its own crash
      // recovery); the server answers its re-upload with already_synced.
      final later = t.add(const Duration(minutes: 3));
      final b = await SyncWorker(queue: queue, gateway: gateway, workerId: 'worker-b', clock: () => later).runOnce();
      expect(b.synced, 1);
      expect((await _op(db, sale)).status, SyncStatus.synced);
      expect(await _ledger(db), before);
    });

    test('a local queue failure ends the run without throwing and a later run recovers', () async {
      final file = File('${Directory.systemTemp.createTempSync('r1_6_').path}/device.sqlite');
      var db = await _device(file);
      final sale = await _sell(db);
      final gateway = _Gateway([_accepted]);
      gateway.onUpload = () => db.close(); // the app closes mid-upload
      final t = DateTime.utc(2026, 10, 2, 9);
      // Must not throw although completeLease hits a closed database.
      final result = await SyncWorker(
        queue: SyncQueueRepository(db, shopId: shopId),
        gateway: gateway,
        workerId: 'worker-a',
        clock: () => t,
      ).runOnce();
      expect((result.synced, result.failed), (0, 1));

      db = AppDatabase(NativeDatabase(file)); // restart
      addTearDown(db.close);
      expect((await _op(db, sale)).status, SyncStatus.syncing, reason: 'still leased, not lost');
      gateway.onUpload = null;
      await _runs(db, gateway, 1, from: t.add(const Duration(seconds: 30)), workerId: 'worker-new');
      expect((await _op(db, sale)).status, SyncStatus.syncing, reason: 'a live lease is never stolen');
      await _runs(db, gateway, 1, from: t.add(const Duration(minutes: 3)), workerId: 'worker-new');
      expect((await _op(db, sale)).status, SyncStatus.synced, reason: 'the expired lease is recovered');
      expect(await db.select(db.sales).get(), hasLength(1));
    });

    test('restart keeps pending, retry-wait, needs-attention, blocked and flagged state', () async {
      final file = File('${Directory.systemTemp.createTempSync('r1_6_').path}/device.sqlite');
      final db = await _device(file);
      final sales = [for (var i = 0; i < 5; i++) await _sell(db, udhaar: i == 4)];
      final script = <String, Object?>{
        sales[1]: const SocketException('offline'),
        sales[2]: _server('DPV01'),
        sales[3]: _server('DPA01'),
        sales[4]: _flagged,
      };
      final gateway = _ByEntityGateway(script);
      await _runs(db, gateway, 1);
      await db.close();

      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);
      final status = {for (final id in sales) id: (await _op(reopened, id)).status};
      expect(status[sales[0]], SyncStatus.synced);
      expect(status[sales[1]], SyncStatus.failed);
      expect(status[sales[2]], SyncStatus.needsAttention);
      expect(status[sales[3]], SyncStatus.blockedAuth);
      expect(status[sales[4]], SyncStatus.synced);
      expect((await _op(reopened, sales[2])).errorCode, 'DPV01');
      expect((await _op(reopened, sales[4])).errorClass, 'flagged');
      expect((await SyncQueueRepository(reopened, shopId: shopId).attention()).map((o) => o.entityId).toSet(),
          {sales[2], sales[3], sales[4]});
    });

    test('runners on one device get distinct worker identities', () {
      final ids = {for (var i = 0; i < 20; i++) uniqueSyncWorkerId('device-$deviceId')};
      expect(ids, hasLength(20));
      expect(ids.every((id) => id.startsWith('device-$deviceId-')), isTrue);
    });
  });

  group('R1.5 sync health', () {
    test('unresolved attention prevents a false Synced', () async {
      final db = await _device();
      addTearDown(db.close);
      final health = <SyncHealth>[];
      final subscription = watchShopSyncHealth(db, shopId).listen(health.add);
      addTearDown(subscription.cancel);
      Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));
      await settle();
      final sale = await _sell(db);
      await settle();
      await _runs(db, _Gateway([_server('DPV01')]), 1);
      await settle();
      final another = await _sell(db);
      await _runs(db, _Gateway([_accepted]), 1);
      await settle();
      expect(health.first, SyncHealth.synced);
      expect(health, contains(SyncHealth.pending));
      final fromAttention = health.skipWhile((h) => h != SyncHealth.needsAttention).toList();
      expect(fromAttention, [SyncHealth.needsAttention],
          reason: 'once attention is needed, a later successful sync never shows Synced: $health');
      expect((await _op(db, another)).status, SyncStatus.synced);
      expect((await _op(db, sale)).status, SyncStatus.needsAttention);
    });
  });
}

/// Answers by sale id, so one run can drive every state.
final class _ByEntityGateway implements SaleUploadGateway {
  _ByEntityGateway(this.script);
  final Map<String, Object?> script;
  @override
  Future<Object?> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) async {
    final saleId = (payload['sale'] as Map)['id'] as String;
    final next = script[saleId];
    if (next is Exception || next is Error) throw next!;
    return next ?? _accepted;
  }
}
