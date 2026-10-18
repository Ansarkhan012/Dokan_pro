// Exactly-once over the real HTTP path (pilot preparation, PROJECT_AUDIT.md
// §4.5). For a sale, a return, a void and a Khata payment that are committed
// locally:
//   1. the upload times out after the server committed (response lost), and
//      the retry is answered already_synced;
//   2. the same queued payload is uploaded twice at once (the first request is
//      still running when a retry or another sync run starts);
//   3. two sync runs on one device race for the same queue.
// Each must leave exactly one copy of every financial row on the server and
// the local operation synced with its payload unchanged.
@Tags(['r1-http'])
library;

import 'dart:convert';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/local_customer_payment_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:dukaan_pro/sync/supabase_sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart';

void main() {
  late LocalHttpStack stack;
  final devices = <SimDevice>[];
  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

  setUpAll(() async {
    if (r1HttpConfigured) stack = await LocalHttpStack.connect();
  });
  tearDown(() async {
    for (final device in devices) {
      await device.dispose();
    }
    devices.clear();
  });
  tearDownAll(() async {
    if (r1HttpConfigured) await stack.dispose();
  });

  Future<(ServerShop, SimDevice)> setup() async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final device = await SimDevice.open('a', shop, shop.deviceA);
    devices.add(device);
    return (shop, device);
  }

  Future<int> count(ServerShop shop, String table, String column, String value) async =>
      (await shop.owner.client.from(table).select('id').eq(column, value) as List).length;

  /// A credit sale of 2 Coke (Rs 360 Udhaar), already synced.
  Future<String> syncedCreditSale(SimDevice a) async {
    final sale = await LocalSaleService(a.db, const UuidV7Generator(), clock: a.now).createSale(
      SaleDraft(
        shopId: a.shop.shopId,
        cashierId: a.shop.owner.userId,
        deviceId: a.deviceId,
        customerId: a.shop.customerId,
        lines: [SaleLineDraft(productId: a.shop.productId, quantity: 2000)],
        payments: const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 36000)],
      ),
    );
    expect((await a.sync()).synced, 1);
    return sale.saleId;
  }

  Future<String> returnOne(SimDevice a, String saleId) async {
    final item = await (a.db.select(a.db.saleItems)..where((t) => t.saleId.equals(saleId))).getSingle();
    return (await LocalSaleReturnService(a.db, const UuidV7Generator(), clock: a.now).create(
      SaleReturnDraft(
        shopId: a.shop.shopId, originalSaleId: saleId, ownerId: a.shop.owner.userId,
        deviceId: a.deviceId, refundMethod: PaymentMethod.credit, reason: 'damaged',
        lines: [SaleReturnLineDraft(originalSaleItemId: item.id, quantity: 1000)],
      ),
    )).returnId;
  }

  Future<String> voidSale(SimDevice a, String saleId) =>
      LocalSaleVoidService(a.db, const UuidV7Generator(), clock: a.now).voidSale(
        shopId: a.shop.shopId, saleId: saleId, ownerId: a.shop.owner.userId,
        deviceId: a.deviceId, reason: 'wrong bill');

  /// Receives Rs 100 against the Udhaar; returns the ledger entry id.
  Future<String> receive(SimDevice a) async {
    final opId = await LocalCustomerPaymentService(a.db, const UuidV7Generator(), clock: a.now).receive(
      shopId: a.shop.shopId, customerId: a.shop.customerId, actorId: a.shop.owner.userId,
      deviceId: a.deviceId, amountMinor: 10000, method: PaymentMethod.cash);
    return (await (a.db.select(a.db.syncOperations)..where((t) => t.id.equals(opId))).getSingle()).entityId;
  }

  /// Server rows that one applied operation creates, keyed for comparison.
  Future<Map<String, int>> serverRows(ServerShop shop, String kind, String id) async => switch (kind) {
        'sale' => {
            'sales': await count(shop, 'sales', 'id', id),
            'movements': await count(shop, 'inventory_movements', 'reference_id', id),
            'payments': await count(shop, 'sale_payments', 'sale_id', id),
          },
        'return' => {
            'returns': await count(shop, 'sale_returns', 'id', id),
            'items': await count(shop, 'sale_return_items', 'return_id', id),
            'movements': await count(shop, 'inventory_movements', 'reference_id', id),
          },
        'void' => {
            'voids': await count(shop, 'sale_voids', 'id', id),
            'movements': await count(shop, 'inventory_movements', 'reference_id', id),
          },
        _ => {'ledger': await count(shop, 'customer_ledger_entries', 'id', id)},
      };

  /// The single unsynced operation for [entityId] on the device.
  Future<String> payloadOf(SimDevice a, String entityId) async =>
      (await a.queue()).singleWhere((o) => o.entityId == entityId).payload;

  /// Builds one operation of [kind] on a fresh shop; returns (entity id,
  /// expected server rows once applied).
  Future<(String, Map<String, int>)> prepare(SimDevice a, String kind) async {
    switch (kind) {
      case 'sale':
        final sale = await a.sell(quantity: 1000);
        return (sale.saleId, {'sales': 1, 'movements': 1, 'payments': 1});
      case 'return':
        return (await returnOne(a, await syncedCreditSale(a)), {'returns': 1, 'items': 1, 'movements': 1});
      case 'void':
        return (await voidSale(a, await syncedCreditSale(a)), {'voids': 1, 'movements': 1});
      default:
        await syncedCreditSale(a);
        return (await receive(a), {'ledger': 1});
    }
  }

  for (final kind in ['sale', 'return', 'void', 'payment']) {
    test('$kind: response lost after the server committed, then retry → applied once', () async {
      final (shop, a) = await setup();
      final (id, expected) = await prepare(a, kind);
      final queued = await payloadOf(a, id);
      a.network = SimNetwork.dropResponse;
      expect((await a.sync()).failed, 1, reason: 'server committed, response lost');
      expect(await serverRows(shop, kind, id), expected, reason: 'committed once');
      a.network = SimNetwork.online;
      a.clockSkew = const Duration(minutes: 10); // past the retry backoff
      expect((await a.sync()).synced, 1, reason: 'the retry is already_synced');
      expect(await serverRows(shop, kind, id), expected, reason: 'still once after the retry');
      final op = (await a.queue()).singleWhere((o) => o.entityId == id);
      expect(op.status, SyncStatus.synced);
      expect(op.payload, queued, reason: 'the retry re-sends the same payload');
    }, skip: skip);

    test('$kind: the same payload uploaded twice at once → applied once, both answered', () async {
      final (shop, a) = await setup();
      final (id, expected) = await prepare(a, kind);
      final payload = jsonDecode(await payloadOf(a, id)) as Map<String, dynamic>;
      final gateway = SupabaseSaleUploadGateway(shop.owner.client);
      final results = await Future.wait([
        gateway.uploadSaleAggregate(payload),
        gateway.uploadSaleAggregate(payload),
      ]);
      final statuses = [for (final r in results) (r as Map)['status']]..sort();
      expect(statuses, ['already_synced', 'inserted']);
      expect(await serverRows(shop, kind, id), expected);
    }, skip: skip);
  }

  test('two sync runs racing on one device upload each operation once', () async {
    final (shop, a) = await setup();
    final sales = [for (var i = 0; i < 4; i++) (await a.sell(quantity: 1000)).saleId];
    final gateway = SupabaseSaleUploadGateway(shop.owner.client);
    SyncWorker worker(String id) => SyncWorker(
          queue: SyncQueueRepository(a.db, shopId: shop.shopId),
          gateway: gateway,
          workerId: id,
          clock: a.now,
        );
    final runs = await Future.wait([worker('w1').runOnce(), worker('w2').runOnce()]);
    expect(runs.fold<int>(0, (n, r) => n + r.synced), 4);
    expect(runs.fold<int>(0, (n, r) => n + r.failed), 0);
    for (final id in sales) {
      expect(await serverRows(shop, 'sale', id), {'sales': 1, 'movements': 1, 'payments': 1});
    }
    expect((await a.queue()).every((o) => o.status == SyncStatus.synced), isTrue);
  }, skip: skip);

  test('a pending void waits for its sale even when both are queued offline', () async {
    final (shop, a) = await setup();
    a.network = SimNetwork.offline;
    final sale = await a.sell(quantity: 1000);
    final voidId = await voidSale(a, sale.saleId);
    expect((await a.sync()).failed, 1, reason: 'the sale fails offline; the void waits behind it');
    final voidOp = (await a.queue()).singleWhere((o) => o.entityId == voidId);
    expect(voidOp.status, SyncStatus.pending, reason: 'never attempted before its sale');
    expect(voidOp.dependsOnOperationId, isNotNull);
    a.network = SimNetwork.online;
    a.clockSkew = const Duration(minutes: 10);
    expect((await a.sync()).synced, 2);
    expect(await serverRows(shop, 'void', voidId), {'voids': 1, 'movements': 1});
  }, skip: skip);
}
