// R1.4 sync order through the real HTTP path (PostgREST pull with the
// (server_seq, id) cursor): a late offline upload and a fast-clock device
// reach the other device, and a second owner never sees this shop's rows.
//
// 'R1.4 server_seq: pulled rows expose a server-assigned order' moved here
// from red/http_contract_red_test.dart by R1.4, name and assertions unchanged.
@Tags(['r1-http'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/supabase_reference_pull_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart';

String _id() => const Uuid().v4();
String _now() => DateTime.now().toUtc().toIso8601String();

/// A hand-built v1 sale aggregate (the shape the R1.3 HTTP tests use).
Map<String, dynamic> _sale(ServerShop shop, {required String saleId}) {
  final at = _now();
  return {
    'version': 1,
    'operation': 'sync_sale_transaction',
    'audit_id': _id(),
    'sale': {
      'id': saleId, 'shopId': shop.shopId, 'cashierId': shop.owner.userId, 'customerId': null,
      'deviceId': shop.deviceA, 'invoiceNumber': null, 'subtotal': ServerShop.salePrice,
      'discountTotal': 0, 'taxTotal': 0, 'grandTotal': ServerShop.salePrice,
      'paymentStatus': 'paid', 'saleStatus': 'completed', 'createdAt': at,
    },
    'sale_items': [
      {
        'id': _id(), 'productId': shop.productId, 'productNameSnapshot': 'Coke', 'barcodeSnapshot': null,
        'quantity': 1000, 'costPriceSnapshot': 15000, 'salePriceSnapshot': ServerShop.salePrice,
        'discountAmount': 0, 'lineTotal': ServerShop.salePrice, 'createdAt': at,
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

  Future<String> sellAt(SimDevice d, DateTime at) async =>
      (await LocalSaleService(d.db, const UuidV7Generator(), clock: () => at).createSale(SaleDraft(
        shopId: d.shop.shopId,
        cashierId: d.shop.owner.userId,
        deviceId: d.deviceId,
        lines: [SaleLineDraft(productId: d.shop.productId, quantity: 1000)],
        payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: ServerShop.salePrice)],
      )))
          .saleId;

  test('late offline upload and a fast-clock device both reach device B over HTTP; B converges', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    final b = await device('b', shop, shop.deviceB);
    final now = DateTime.now().toUtc();
    a.network = SimNetwork.offline;
    final late = await sellAt(a, now.subtract(const Duration(hours: 3)));
    expect((await a.sync()).failed, 1);
    final future = await sellAt(b, now.add(const Duration(days: 1)));
    expect((await b.sync()).synced, 1);
    await b.pull();
    final normal = await sellAt(b, now);
    expect((await b.sync()).synced, 1);
    a.network = SimNetwork.online;
    a.clockSkew = const Duration(minutes: 10);
    expect((await a.sync()).synced, 1, reason: 'the late upload');
    await b.pull();
    await b.pull();
    for (final id in [late, future, normal]) {
      expect(await b.hasSale(id), isTrue, reason: id);
    }
    await a.pull();
    final serverStock = (await shop.owner.client.from('inventory_movements').select('quantity')
            .eq('product_id', shop.productId) as List)
        .fold<int>(0, (sum, r) => sum + ((r as Map)['quantity'] as int));
    expect(await a.stock(shop.productId), serverStock);
    expect(await b.stock(shop.productId), serverStock);
    expect(serverStock, ServerShop.openingStock - 3000);
    final seqs = await shop.owner.client.from('sales').select('server_seq').eq('shop_id', shop.shopId) as List;
    expect(seqs.map((r) => (r as Map)['server_seq']).toSet(), hasLength(3), reason: 'one position per upload');
  }, skip: skip);

  test('another owner pulling this shop by HTTP gets nothing, whatever the cursor', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await device('a', shop, shop.deviceA);
    await sellAt(a, DateTime.now().toUtc());
    expect((await a.sync()).synced, 1);
    final stranger = await stack.signUpOwner();
    final gateway = SupabaseReferencePullGateway(stranger.client);
    for (final entity in [PullEntity.sales, PullEntity.inventoryMovements, PullEntity.shopProducts, PullEntity.shops]) {
      expect(await gateway.fetch(entity: entity, shopId: shop.shopId), isEmpty, reason: entity.name);
      expect(
        await gateway.fetch(
          entity: entity,
          shopId: shop.shopId,
          after: PullCursor(updatedAt: DateTime.utc(2000), entityId: '', serverSeq: -1),
        ),
        isEmpty,
        reason: entity.name,
      );
    }
  }, skip: skip);

  // Moved unchanged from the expected-red suite (R1.4 delivered server_seq).
  test('R1.4 server_seq: pulled rows expose a server-assigned order', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final saleId = _id();
    await _rpc(shop, 'sync_sale_transaction', _sale(shop, saleId: saleId));
    try {
      final row = await shop.owner.client.from('sales').select('id,server_seq').eq('id', saleId).single();
      expect(row['server_seq'], isA<int>());
    } catch (e) {
      if (e is TestFailure) rethrow;
      fail('server_seq is not available through PostgREST: ${ServerError.of(e) ?? e}');
    }
  }, skip: skip);
}
