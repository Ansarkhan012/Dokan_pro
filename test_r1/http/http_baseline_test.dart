// R1 HTTP integration suite (green): behaviour that already holds through the
// real Supabase HTTP path and must stay green through every R1 substage.
@Tags(['r1-http'])
library;

import 'dart:convert';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/sync/supabase_sale_upload_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/http_stack.dart';
import '../support/legacy_zero_payment.dart';
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

  Future<ServerShop> newShop({int? creditLimit}) async =>
      ServerShop.create(await stack.signUpOwner(), creditLimit: creditLimit);
  Future<SimDevice> device(String label, ServerShop shop, String id) async {
    final d = await SimDevice.open(label, shop, id);
    devices.add(d);
    return d;
  }

  Future<int> serverCount(ServerShop shop, String table, String column, String value) async =>
      (await shop.owner.client.from(table).select('id').eq(column, value) as List).length;

  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

  test('owner, shop, devices, products and customer are created through public APIs', () async {
    final shop = await newShop(creditLimit: 30000);
    final client = shop.owner.client;
    expect((await client.from('shops').select('id').eq('id', shop.shopId) as List), hasLength(1));
    expect((await client.from('devices').select('id').eq('shop_id', shop.shopId) as List), hasLength(2));
    expect((await client.from('shop_products').select('id').eq('shop_id', shop.shopId) as List), hasLength(2));
    final customer = await client.from('customers').select('credit_limit').eq('id', shop.customerId).single();
    expect(customer['credit_limit'], 30000);
  }, skip: skip);

  test('two independent device databases seed through the real pull path', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    final b = await device('b', shop, shop.deviceB);
    expect(await a.stock(shop.productId), ServerShop.openingStock);
    expect(await b.stock(shop.productId), ServerShop.openingStock);
    expect(identical(a.db, b.db), isFalse);
  }, skip: skip);

  test('sale uploads through SupabaseSaleUploadGateway and SyncWorker', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    final sale = await a.sell();
    final result = await a.sync();
    expect(result.synced, 1);
    expect(await serverCount(shop, 'sales', 'id', sale.saleId), 1);
    expect(await serverCount(shop, 'sale_items', 'sale_id', sale.saleId), 1);
    expect(await serverCount(shop, 'inventory_movements', 'reference_id', sale.saleId), 1);
  }, skip: skip);

  test('exact replay of the same queued payload creates nothing new', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    final sale = await a.sell();
    await a.sync();
    final payload = jsonDecode((await a.queue()).single.payload) as Map<String, dynamic>;
    final gateway = SupabaseSaleUploadGateway(shop.owner.client);
    for (var i = 0; i < 3; i++) {
      await gateway.uploadSaleAggregate(payload);
    }
    expect(await serverCount(shop, 'sales', 'id', sale.saleId), 1);
    expect(await serverCount(shop, 'sale_items', 'sale_id', sale.saleId), 1);
    expect(await serverCount(shop, 'inventory_movements', 'reference_id', sale.saleId), 1);
  }, skip: skip);

  test('lost response after server commit, then retry, yields exactly one sale', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    final sale = await a.sell();
    a.network = SimNetwork.dropResponse;
    expect((await a.sync()).failed, 1);
    expect(await serverCount(shop, 'sales', 'id', sale.saleId), 1);
    a.network = SimNetwork.online;
    a.clockSkew = const Duration(minutes: 10); // past the retry backoff
    expect((await a.sync()).synced, 1);
    expect(await serverCount(shop, 'sales', 'id', sale.saleId), 1);
    expect((await a.queue()).single.status, SyncStatus.synced);
  }, skip: skip);

  test('queued offline sale survives a simulated process restart and then syncs', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    a.network = SimNetwork.offline;
    final sale = await a.sell();
    expect((await a.sync()).failed, 1);
    await a.restart();
    a.network = SimNetwork.online;
    a.clockSkew = const Duration(minutes: 10);
    expect((await a.sync()).synced, 1);
    expect(await serverCount(shop, 'sales', 'id', sale.saleId), 1);
    expect(a.serverUploads, 1);
  }, skip: skip);

  test('an online sale on device A reaches device B through the real pull path', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    final b = await device('b', shop, shop.deviceB);
    final sale = await a.sell(quantity: 2000);
    await a.sync();
    await b.pull();
    expect(await b.hasSale(sale.saleId), isTrue);
    expect(await b.stock(shop.productId), ServerShop.openingStock - 2000);
  }, skip: skip);

  test('server rejection surfaces a structured error code and message', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    // A pre-R1.1 queued aggregate with a Rs 0 cash row: the server rejects it.
    final free = await a.sell(productId: shop.freeProductId, payments: const []);
    await addLegacyZeroCashPayment(a.db, free.saleId);
    final payload = jsonDecode((await a.queue()).single.payload) as Map<String, dynamic>;
    ServerError? error;
    try {
      await SupabaseSaleUploadGateway(shop.owner.client).uploadSaleAggregate(payload);
    } catch (e) {
      error = ServerError.of(e);
    }
    expect(error, isNotNull, reason: 'PostgREST error must be a PostgrestException');
    expect(error!.code, isNotEmpty);
    expect(error.message, isNotEmpty);
  }, skip: skip);

  test('another owner cannot read this shop over HTTP', () async {
    final shop = await newShop();
    final a = await device('a', shop, shop.deviceA);
    final sale = await a.sell();
    await a.sync();
    final stranger = await stack.signUpOwner();
    expect(await stranger.client.from('sales').select('id').eq('id', sale.saleId), isEmpty);
    expect(await stranger.client.from('shops').select('id').eq('id', shop.shopId), isEmpty);
  }, skip: skip);
}
