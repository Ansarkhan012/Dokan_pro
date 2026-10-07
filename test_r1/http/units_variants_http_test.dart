// U1 through the real Supabase HTTP path (Kong -> PostgREST/GoTrue) of a
// disposable LOCAL stack: products created by the owner RPC, loose and pack
// sales uploaded by the app's worker and gateway, stock and snapshots
// converging on two devices, and the cashier device credential path
// (device_pull and a cashier-session upload) carrying the new fields.
@Tags(['r1-http'])
library;

import 'package:drift/native.dart';
import 'package:dukaan_pro/auth/device_credential.dart';
import 'package:dukaan_pro/auth/supabase_cashier_auth_gateway.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/pull/supabase_reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/supabase_sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart';

String _id() => const Uuid().v4();

/// Creates one product through the owner RPC and returns its id.
Future<String> _create(ServerShop shop, Map<String, Object?> fields) async {
  final id = _id();
  await shop.owner.client.rpc('create_shop_product', params: {
    'p_payload': {
      'shop_id': shop.shopId, 'device_id': shop.deviceA, 'product_id': id, 'movement_id': _id(),
      'category_id': ServerShop.categoryId, 'purchase_price': 100, ...fields,
    },
  });
  return id;
}

Future<CreatedSale> _sell(AppDatabase db, ServerShop shop, String cashier, String device, String product, int quantity, int price) =>
    LocalSaleService(db, const UuidV7Generator()).createSale(SaleDraft(
      shopId: shop.shopId, cashierId: cashier, deviceId: device,
      lines: [SaleLineDraft(productId: product, quantity: quantity)],
      payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: (price * quantity + 500) ~/ 1000)],
    ));

void main() {
  late LocalHttpStack stack;
  final devices = <SimDevice>[];
  final clients = <SupabaseClient>[];

  setUpAll(() async {
    if (r1HttpConfigured) stack = await LocalHttpStack.connect();
  });
  tearDown(() async {
    for (final device in devices) {
      await device.dispose();
    }
    devices.clear();
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });
  tearDownAll(() async {
    if (r1HttpConfigured) await stack.dispose();
  });
  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

  test('loose and pack sales converge on two devices with exact grams and snapshots', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final family = _id();
    final atta = await _create(shop, {'name': 'Atta', 'unit': 'kg', 'sell_mode': 'measured', 'sale_price': 13000,
        'opening_quantity': 40000, 'measure_presets': [250, 500, 1000, 2000, 5000]});
    final tapal250 = await _create(shop, {'name': 'Tapal Danedar', 'pack_label': '250 g', 'unit': 'pack',
        'family_id': family, 'sale_price': 41000, 'opening_quantity': 12000, 'barcode': 'U1-TAPAL-250-${_id()}'});
    final tapal500 = await _create(shop, {'name': 'Tapal Danedar', 'pack_label': '500 g', 'unit': 'pack',
        'family_id': family, 'sale_price': 82000, 'opening_quantity': 6000});

    final a = await SimDevice.open('units_a', shop, shop.deviceA);
    final b = await SimDevice.open('units_b', shop, shop.deviceB);
    devices..add(a)..add(b);
    final pulled = await (a.db.select(a.db.shopProducts)..where((t) => t.id.equals(atta))).getSingle();
    expect((pulled.sellMode, pulled.unit, pulled.measurePresets, pulled.allowCustomQuantity),
        ('measured', 'kg', '[250,500,1000,2000,5000]', true));
    final variant = await (a.db.select(a.db.shopProducts)..where((t) => t.id.equals(tapal500))).getSingle();
    expect((variant.sellMode, variant.familyId, variant.packLabel), ('piece', family, '500 g'));

    final owner = shop.owner.userId;
    final loose = await _sell(a.db, shop, owner, shop.deviceA, atta, 2500, 13000);
    final pack = await _sell(a.db, shop, owner, shop.deviceA, tapal250, 2000, 41000);
    await _sell(b.db, shop, owner, shop.deviceB, tapal250, 1000, 41000);
    await _sell(b.db, shop, owner, shop.deviceB, atta, 750, 13000);
    expect((await a.sync()).synced, 2);
    expect((await b.sync()).synced, 2);

    final client = shop.owner.client;
    final item = await client.from('sale_items').select('quantity,line_total,measure_unit_snapshot,product_name_snapshot')
        .eq('sale_id', loose.saleId).single();
    expect(item, {'quantity': 2500, 'line_total': 32500, 'measure_unit_snapshot': 'kg', 'product_name_snapshot': 'Atta'});
    final packItem = await client.from('sale_items').select('product_name_snapshot,measure_unit_snapshot')
        .eq('sale_id', pack.saleId).single();
    expect(packItem, {'product_name_snapshot': 'Tapal Danedar 250 g', 'measure_unit_snapshot': null});

    await a.pull();
    await b.pull();
    for (final device in [a, b]) {
      expect(await device.stock(atta), 40000 - 2500 - 750, reason: device.label);
      expect(await device.stock(tapal250), 12000 - 3000, reason: device.label);
      expect(await device.stock(tapal500), 6000, reason: 'independent variant stock');
      final line = await (device.db.select(device.db.saleItems)..where((t) => t.saleId.equals(loose.saleId))).getSingle();
      expect((line.quantity, line.lineTotal, line.measureUnitSnapshot), (2500, 32500, 'kg'));
    }

    // Another shop sees none of it.
    final other = await ServerShop.create(await stack.signUpOwner());
    final foreign = await other.owner.client.from('shop_products').select('id').inFilter('id', [atta, tapal250, tapal500]);
    expect(foreign, isEmpty);
  }, skip: skip);

  test('the cashier device credential pulls and uploads measured sales', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final rpc = shop.owner.client.rpc;
    final atta = await _create(shop, {'name': 'Atta', 'unit': 'kg', 'sell_mode': 'measured',
        'sale_price': 13000, 'opening_quantity': 40000});
    final identifier = _id();
    final deviceId = (((await rpc('register_shop_device', params: {
      'p_shop_id': shop.shopId, 'p_device_name': 'Counter tablet',
      'p_device_type': 'androidTablet', 'p_device_identifier': identifier,
    })) as List).single as Map)['device_id'] as String;
    final cashierId = await rpc('create_cashier', params: {
      'p_shop_id': shop.shopId, 'p_display_name': 'Ahmed', 'p_login_code': 'ahmed', 'p_pin': '4321',
    }) as String;
    final credential = DeviceCredential(
      shopId: shop.shopId, shopName: 'R1 shop', deviceId: deviceId, deviceIdentifier: identifier,
      secret: await SupabaseDeviceCredentialIssuer(shop.owner.client).issue(shopId: shop.shopId, deviceId: deviceId),
    );
    final client = deviceSupabaseClient(url: stack.url.toString(), anonKey: stack.anonKey, credential: credential);
    clients.add(client);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pull = ReferencePullService(db, DeviceReferencePullGateway(client), shopId: shop.shopId);
    for (final entity in posPullEntities) {
      await pull.pull(entity);
    }
    final product = await (db.select(db.shopProducts)..where((t) => t.id.equals(atta))).getSingle();
    expect((product.sellMode, product.unit), ('measured', 'kg'), reason: 'device_pull carries the selling mode');

    final session = await SupabaseCashierAuthGateway(client).authenticate(
      shopId: shop.shopId, deviceIdentifier: identifier, cashierId: cashierId, pin: '4321');
    final sale = await _sell(db, shop, cashierId, deviceId, atta, 1250, 13000);
    final result = await SyncWorker(
      queue: SyncQueueRepository(db, shopId: shop.shopId),
      gateway: SupabaseSaleUploadGateway(client),
      workerId: 'units-cashier',
      cashierToken: () async => session.token,
    ).runOnce();
    expect(result.synced, 1);

    for (final entity in posPullEntities) {
      await pull.pull(entity);
    }
    final line = await (db.select(db.saleItems)..where((t) => t.saleId.equals(sale.saleId))).getSingle();
    expect((line.quantity, line.lineTotal, line.measureUnitSnapshot), (1250, 16250, 'kg'));
    final server = await shop.owner.client.from('sale_items').select('measure_unit_snapshot,line_total')
        .eq('sale_id', sale.saleId).single();
    expect(server, {'measure_unit_snapshot': 'kg', 'line_total': 16250});
  }, skip: skip);
}
