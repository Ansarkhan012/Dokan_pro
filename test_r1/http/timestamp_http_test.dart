// R1.2 timestamp correctness through the real HTTP path (Drift → outbox →
// SupabaseSaleUploadGateway → PostgREST RPC → PostgreSQL → pull). Server
// values are read back over PostgREST as timestamptz JSON with an explicit
// offset and compared with fixed instants. Run under TZ=UTC, Asia/Karachi
// and EST5.
@Tags(['r1-http'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value, ValueSerializer;
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart';

/// 10:00 in Pakistan on 30 Sep 2026.
final _soldAt = DateTime.utc(2026, 9, 30, 5);

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

  Future<CreatedSale> sellAt(SimDevice d, DateTime at) =>
      LocalSaleService(d.db, const UuidV7Generator(), clock: () => at).createSale(SaleDraft(
        shopId: d.shop.shopId,
        cashierId: d.shop.owner.userId,
        deviceId: d.deviceId,
        lines: [SaleLineDraft(productId: d.shop.productId, quantity: 1000)],
        payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000)],
      ));

  /// created_at of every server row of one sale, as PostgREST returns it.
  Future<List<String>> serverStamps(ServerShop shop, String saleId) async {
    final c = shop.owner.client;
    return [
      for (final (table, column) in [
        ('sales', 'id'),
        ('sale_items', 'sale_id'),
        ('sale_payments', 'sale_id'),
        ('inventory_movements', 'reference_id'),
      ])
        for (final row in await c.from(table).select('created_at').eq(column, saleId) as List)
          (row as Map)['created_at'] as String,
    ];
  }

  void expectInstant(List<String> stamps, DateTime instant) {
    expect(stamps, hasLength(4));
    for (final stamp in stamps) {
      expect(stamp, matches(RegExp(r'(Z|[+-]\d\d:\d\d)$')), reason: 'server sends an explicit offset');
      expect(DateTime.parse(stamp).isAtSameMomentAs(instant), isTrue, reason: '$stamp vs $instant');
    }
  }

  test('A/D: an offline Pakistan sale uploaded after a restart keeps its event instant', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    a.network = SimNetwork.offline;
    final sale = await sellAt(a, _soldAt);
    expect((await a.sync()).failed, 1);
    final queued = (await a.queue()).single.payload;
    await a.restart();
    a.network = SimNetwork.online;
    a.clockSkew = const Duration(hours: 3);
    expect((await a.sync()).synced, 1);
    expect((await a.queue()).single.payload, queued);
    expectInstant(await serverStamps(shop, sale.saleId), _soldAt);
    final server = await shop.owner.client.from('sales').select('synced_at').eq('id', sale.saleId).single();
    expect(DateTime.parse(server['synced_at'] as String).isAfter(_soldAt), isTrue,
        reason: 'sync time is recorded separately and never replaces the event time');
  }, skip: skip);

  test('E: a lost response and a retry keep one aggregate, one identity and one instant', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    final sale = await sellAt(a, _soldAt);
    final queued = (await a.queue()).single.payload;
    a.network = SimNetwork.dropResponse;
    expect((await a.sync()).failed, 1, reason: 'server committed, response lost');
    a.network = SimNetwork.online;
    a.clockSkew = const Duration(minutes: 10);
    expect((await a.sync()).synced, 1, reason: 'the retry is already_synced');
    expect(a.serverUploads, 2);
    final op = (await a.queue()).single;
    expect(op.payload, queued, reason: 'the retry sends the original payload, no new timestamp');
    expect(op.entityId, sale.saleId);
    final c = shop.owner.client;
    expect(await c.from('sales').select('id').eq('id', sale.saleId), hasLength(1));
    expect(await c.from('sale_items').select('id').eq('sale_id', sale.saleId), hasLength(1));
    expect(await c.from('inventory_movements').select('id').eq('reference_id', sale.saleId), hasLength(1));
    expectInstant(await serverStamps(shop, sale.saleId), _soldAt);
  }, skip: skip);

  test('F: device B pulls device A\'s Pakistan sale and resolves the same instant', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    final b = await device('b', shop, shop.deviceB);
    final sale = await sellAt(a, _soldAt);
    expect((await a.sync()).synced, 1);
    await b.pull();
    final pulled = await (b.db.select(b.db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    final own = await (a.db.select(a.db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    expect(pulled.createdAt.isAtSameMomentAs(_soldAt), isTrue, reason: '${pulled.createdAt}');
    expect(pulled.createdAt.isAtSameMomentAs(own.createdAt), isTrue);
    final rowOnB = await DriftSalesHistoryRepository(b.db, shopId: shop.shopId).sale(sale.saleId);
    expect(rowOnB?.at, DateTime.utc(2026, 9, 30, 5));
    for (final item in await (b.db.select(b.db.saleItems)..where((t) => t.saleId.equals(sale.saleId))).get()) {
      expect(item.createdAt.isAtSameMomentAs(_soldAt), isTrue);
    }
  }, skip: skip);

  test('legacy offset-less queued sale is refused over HTTP and never reaches the server', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    final sale = await sellAt(a, _soldAt);
    // The pre-R1.2 queued shape: Drift's default string encoding (no offset).
    const legacy = ValueSerializer.defaults(serializeDateTimeValuesAsString: true);
    final row = await (a.db.select(a.db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    final payload = jsonDecode((await a.queue()).single.payload) as Map<String, dynamic>;
    payload['sale'] = row.toJson(serializer: legacy);
    final text = jsonEncode(payload);
    await (a.db.update(a.db.syncOperations)..where((t) => t.entityId.equals(sale.saleId)))
        .write(SyncOperationsCompanion(payload: Value(text)));
    expect((await a.sync()).failed, 1);
    final op = (await a.queue()).single;
    expect(op.status, SyncStatus.failed);
    expect(op.lastError, contains('AmbiguousTimestampPayload'));
    expect(op.payload, text);
    expect(await shop.owner.client.from('sales').select('id').eq('id', sale.saleId), isEmpty);
    expect(a.serverUploads, 0);
  }, skip: skip);
}
