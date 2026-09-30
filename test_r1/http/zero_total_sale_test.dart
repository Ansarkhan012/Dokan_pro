// R1.1 zero-total contract through the real HTTP path (design §J): a sale
// whose grand total is exactly Rs 0 carries NO payment rows, is accepted by
// the existing sync_sale_transaction (no server change), keeps its stock
// movement, and an exact replay is already_synced.
@Tags(['r1-http'])
library;

import 'dart:convert';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart';

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

  test('zero-total sale with no payment rows syncs over HTTP, then replays as already_synced', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final a = await SimDevice.open('zero', shop, shop.deviceA);
    devices.add(a);
    final sale = await a.sell(productId: shop.freeProductId, payments: const []);
    expect(sale.grandTotalMinor, 0);
    final operation = (await a.queue()).single;
    final payload = jsonDecode(operation.payload) as Map<String, dynamic>;
    expect(payload['payments'], isEmpty);

    // The app's own worker and gateway upload it.
    final result = await a.sync();
    expect(result.synced, 1);
    expect((await a.queue()).single.status, SyncStatus.synced);

    final client = shop.owner.client;
    final server = await client.from('sales').select('grand_total').eq('id', sale.saleId).single();
    expect(server['grand_total'], 0);
    expect(await client.from('sale_payments').select('id').eq('sale_id', sale.saleId), isEmpty);
    expect(await client.from('sale_items').select('id').eq('sale_id', sale.saleId), hasLength(1));
    final movements = await client
        .from('inventory_movements')
        .select('quantity')
        .eq('reference_id', sale.saleId) as List;
    expect(movements.map((m) => (m as Map)['quantity']), [-1000]);

    final replay = await client.rpc('sync_sale_transaction', params: {
      'p_payload': normalizeSalePayloadForCloud(payload),
      'p_cashier_token': null,
    }) as Map;
    expect(replay['status'], 'already_synced');
    expect(await client.from('sales').select('id').eq('id', sale.saleId), hasLength(1));
  }, skip: skip);
}
