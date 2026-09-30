// R1.3 (F-2) void convergence through the real HTTP path: Drift → outbox →
// SupabaseSaleUploadGateway → PostgREST sync_sale_void (v2) → PostgreSQL →
// pull → Drift, on two independent file-backed devices.
//
// 'R1.3 v2 void: server uses the client compensation ids' moved here from
// red/http_contract_red_test.dart by R1.3, name and assertions unchanged.
@Tags(['r1-http'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart';

String _id() => const Uuid().v4();
String _now() => DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _sale(
  ServerShop shop, {
  required String saleId,
}) {
  final at = _now();
  final itemId = _id();
  return {
    'version': 1,
    'operation': 'sync_sale_transaction',
    'audit_id': _id(),
    'sale': {
      'id': saleId,
      'shopId': shop.shopId,
      'cashierId': shop.owner.userId,
      'customerId': null,
      'deviceId': shop.deviceA,
      'invoiceNumber': null,
      'subtotal': ServerShop.salePrice,
      'discountTotal': 0,
      'taxTotal': 0,
      'grandTotal': ServerShop.salePrice,
      'paymentStatus': 'paid',
      'saleStatus': 'completed',
      'createdAt': at,
    },
    'sale_items': [
      {
        'id': itemId,
        'productId': shop.productId,
        'productNameSnapshot': 'Coke',
        'barcodeSnapshot': null,
        'quantity': 1000,
        'costPriceSnapshot': 15000,
        'salePriceSnapshot': ServerShop.salePrice,
        'discountAmount': 0,
        'lineTotal': ServerShop.salePrice,
        'createdAt': at,
      },
    ],
    'payments': [
      {'id': _id(), 'paymentMethod': 'cash', 'amount': ServerShop.salePrice, 'reference': null, 'createdAt': at},
    ],
    'inventory_movements': [
      {'id': _id(), 'productId': shop.productId, 'type': 'sale', 'quantity': -1000, 'createdAt': at},
    ],
    'customer_ledger_entries': [],
  };
}

Future<Object?> _rpc(ServerShop shop, String name, Map<String, dynamic> payload) =>
    shop.owner.client.rpc(name, params: {'p_payload': payload, 'p_cashier_token': null});

void main() {
  late LocalHttpStack stack;
  final devices = <SimDevice>[];
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
  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

  Future<SimDevice> device(String label, ServerShop shop, String id) async {
    final d = await SimDevice.open(label, shop, id);
    devices.add(d);
    return d;
  }

  Future<(String, String)> sellAndVoid(SimDevice a) async {
    final shop = a.shop;
    final sale = await LocalSaleService(a.db, const UuidV7Generator()).createSale(SaleDraft(
      shopId: shop.shopId,
      cashierId: shop.owner.userId,
      deviceId: a.deviceId,
      customerId: shop.customerId,
      lines: [SaleLineDraft(productId: shop.productId, quantity: 2000)],
      payments: const [
        SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 10000),
        SalePaymentDraft(method: PaymentMethod.digital, amountMinor: 6000),
        SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 20000),
      ],
    ));
    expect((await a.sync()).synced, 1);
    final voidId = await LocalSaleVoidService(a.db, const UuidV7Generator()).voidSale(
      shopId: shop.shopId, saleId: sale.saleId, ownerId: shop.owner.userId, deviceId: a.deviceId, reason: 'wrong bill');
    return (sale.saleId, voidId);
  }

  /// Everything the devices and the server must agree on for one voided sale.
  Future<String> deviceState(AppDatabase db, ServerShop shop, String saleId, String voidId) async {
    Future<String> q(String sql, List<Object> vars) async => (await db
            .customSelect(sql, variables: [for (final v in vars) Variable(v)])
            .get())
        .map((r) => r.data.values.join(':'))
        .join(',');
    return [
      await q('select id from sale_voids where original_sale_id=? order by id', [saleId]),
      await q("select id, product_id, quantity from inventory_movements where reference_id=? order by id", [voidId]),
      await q("select id, amount from customer_ledger_entries where type='refund' and sale_id=? order by id", [saleId]),
      await q('select coalesce(sum(quantity),0) from inventory_movements where product_id=?', [shop.productId]),
      await q("select coalesce(sum(case when type in ('openingBalance','creditSale','adjustment') then amount else -amount end),0) "
          'from customer_ledger_entries where customer_id=?', [shop.customerId]),
    ].join(' | ');
  }

  Future<String> serverState(ServerShop shop, String saleId, String voidId) async {
    final c = shop.owner.client;
    String rows(List<dynamic> list, List<String> keys) =>
        (list.map((r) => keys.map((k) => '${(r as Map)[k]}').join(':')).toList()..sort()).join(',');
    final voids = await c.from('sale_voids').select('id').eq('original_sale_id', saleId) as List;
    final moves = await c.from('inventory_movements').select('id,product_id,quantity').eq('reference_id', voidId) as List;
    final refunds = await c.from('customer_ledger_entries').select('id,amount').eq('type', 'refund').eq('sale_id', saleId) as List;
    final stock = await c.from('inventory_movements').select('quantity').eq('product_id', shop.productId) as List;
    final ledger = await c.from('customer_ledger_entries').select('type,amount').eq('customer_id', shop.customerId) as List;
    final balance = ledger.fold<int>(0, (sum, r) {
      final m = r as Map;
      final sign = const {'openingBalance', 'creditSale', 'adjustment'}.contains(m['type']) ? 1 : -1;
      return sum + sign * (m['amount'] as int);
    });
    return [
      rows(voids, ['id']),
      rows(moves, ['id', 'product_id', 'quantity']),
      rows(refunds, ['id', 'amount']),
      stock.fold<int>(0, (s, r) => s + ((r as Map)['quantity'] as int)),
      balance,
    ].join(' | ');
  }

  // Moved unchanged from the expected-red suite (R1.3 contract delivered).
  test('R1.3 v2 void: server uses the client compensation ids', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final saleId = _id();
    final sale = _sale(shop, saleId: saleId);
    await _rpc(shop, 'sync_sale_transaction', sale);
    final saleItemId = ((sale['sale_items'] as List).single as Map)['id'] as String;
    final voidId = _id(), movementId = _id();
    try {
      await _rpc(shop, 'sync_sale_void', {
        'version': 2,
        'operation': 'sync_sale_void',
        'void': {
          'id': voidId,
          'shop_id': shop.shopId,
          'original_sale_id': saleId,
          'device_id': shop.deviceA,
          'amount': ServerShop.salePrice,
          'reason': 'wrong item',
          'payment_breakdown': {'cash': ServerShop.salePrice},
          'created_by': shop.owner.userId,
          'created_at': _now(),
        },
        'movement_ids': {saleItemId: movementId},
        'refund_ledger_id': null,
        'audit_id': _id(),
      });
    } catch (e) {
      fail('v2 void was rejected: ${ServerError.of(e) ?? e}');
    }
    final rows = await shop.owner.client
        .from('inventory_movements')
        .select('id')
        .eq('reference_id', voidId) as List;
    final serverIds = rows.map((r) => (r as Map)['id']).toList();
    // ignore: avoid_print
    print('V2VOID_EVIDENCE client movement id=$movementId server ids=$serverIds');
    expect(serverIds, [movementId]);
  }, skip: skip);

  test('legacy v1 void over HTTP returns the stable code DPV01 and writes nothing', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final saleId = _id();
    final sale = _sale(shop, saleId: saleId);
    await _rpc(shop, 'sync_sale_transaction', sale);
    Object? error;
    try {
      await _rpc(shop, 'sync_sale_void', {
        'version': 1,
        'operation': 'sync_sale_void',
        'void': {
          'id': _id(),
          'shop_id': shop.shopId,
          'original_sale_id': saleId,
          'device_id': shop.deviceA,
          'amount': ServerShop.salePrice,
          'reason': 'wrong item',
          'payment_breakdown': {'cash': ServerShop.salePrice},
          'created_by': shop.owner.userId,
          'created_at': _now(),
        },
        'audit_id': _id(),
      });
    } catch (e) {
      error = e;
    }
    expect(ServerError.of(error!)?.code, 'DPV01');
    expect(await shop.owner.client.from('sale_voids').select('id').eq('original_sale_id', saleId), isEmpty);
    expect(await shop.owner.client.from('inventory_movements').select('id').eq('reference_type', 'sale_void'), isEmpty);
  }, skip: skip);

  test('E: a lost void response and a retry make one void and one compensation per effect', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    final (saleId, voidId) = await sellAndVoid(a);
    final queued = (await a.queue()).singleWhere((o) => o.entityId == voidId).payload;
    a.network = SimNetwork.dropResponse;
    expect((await a.sync()).failed, 1, reason: 'server committed, response lost');
    a.network = SimNetwork.online;
    a.clockSkew = const Duration(minutes: 10); // past the retry backoff
    expect((await a.sync()).synced, 1, reason: 'the retry is already_synced');
    final op = (await a.queue()).singleWhere((o) => o.entityId == voidId);
    expect(op.payload, queued, reason: 'no new compensation ids on retry');
    expect(op.status, SyncStatus.synced);
    final server = await serverState(shop, saleId, voidId);
    expect(server, await deviceState(a.db, shop, saleId, voidId));
    expect(server.split(' | ')[0].split(','), hasLength(1));
    expect(server.split(' | ')[1].split(','), hasLength(1));
    expect(server.split(' | ')[2], endsWith(':20000'));
  }, skip: skip);

  test('F: two devices and PostgreSQL converge on the void, its ids, stock and Udhaar', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    final b = await device('b', shop, shop.deviceB);
    final (saleId, voidId) = await sellAndVoid(a);
    expect((await a.sync()).synced, 1);
    await b.pull();
    await a.pull();
    await a.pull();
    await b.pull();
    final server = await serverState(shop, saleId, voidId);
    final onA = await deviceState(a.db, shop, saleId, voidId);
    final onB = await deviceState(b.db, shop, saleId, voidId);
    // ignore: avoid_print
    print('F2_HTTP_EVIDENCE\n  server $server\n  A      $onA\n  B      $onB');
    expect(onA, server);
    expect(onB, server);
    final parts = server.split(' | ');
    expect(parts[3], '${ServerShop.openingStock}', reason: 'stock back to opening');
    expect(parts[4], '0', reason: 'Udhaar back to zero');
    expect(await b.hasSale(saleId), isTrue);
  }, skip: skip);
}
