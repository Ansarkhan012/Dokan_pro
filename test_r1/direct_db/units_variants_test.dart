// U1 server contract (migration 202610080001): selling modes, the measure
// snapshot, old queued payloads, family safety, per-shop barcodes, the cashier
// pull, exact void restoration, cumulative partial returns, and the upgrade
// from the 22-migration schema (including the read-only duplicate preflight).
@Tags(['r1-direct-db'])
// Every RPC is a `docker exec psql` round trip; upgrade tests also build a
// 22-migration scratch database inside the test.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/direct_db_server.dart';

String _id() => const Uuid().v4();
String _q(String v) => "'${v.replaceAll("'", "''")}'";

/// Rs 130/kg loose atta, and Rs 13.33/kg dal (a price whose thirds round up).
const _attaPrice = 13000, _dalPrice = 1333;

/// A measured product on the server and on the device, with opening stock.
Future<String> _addMeasured(ShopFixture f, AppDatabase db, String name, int price, {int opening = 40000}) async {
  final id = _id(), movement = _id();
  await psql('''
insert into public.shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,sell_mode,measure_presets,created_at,updated_at)
  values(${_q(id)},${_q(f.shopId)},${_q(name)},${_q(f.categoryId)},'kg',${price - 100},$price,'measured','{250,500,1000}',now(),now());
insert into public.inventory_movements(id,shop_id,product_id,type,quantity,reference_type,created_by,device_id,created_at)
  values(${_q(movement)},${_q(f.shopId)},${_q(id)},'openingStock',$opening,'product_setup',${_q(f.ownerId)},${_q(f.deviceA)},'2026-01-01T00:00:00Z');
''');
  await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
    id: id, shopId: f.shopId, customName: Value(name), unit: const Value('kg'),
    sellMode: Value(SellMode.measured.name), purchasePrice: price - 100, salePrice: price,
    createdAt: f.seededAt, updatedAt: f.seededAt,
  ));
  await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
    id: movement, shopId: f.shopId, productId: id, type: InventoryMovementType.openingStock,
    quantity: opening, createdBy: f.ownerId, deviceId: Value(f.deviceA), createdAt: DateTime.utc(2026),
  ));
  return id;
}

Future<CreatedSale> _sell(AppDatabase db, ShopFixture f, String product, int quantity, int price) =>
    LocalSaleService(db, const UuidV7Generator()).createSale(SaleDraft(
      shopId: f.shopId, cashierId: f.ownerId, deviceId: f.deviceA,
      lines: [SaleLineDraft(productId: product, quantity: quantity)],
      payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: (price * quantity + 500) ~/ 1000)],
    ));

Future<Map<String, dynamic>> _payloadOf(AppDatabase db, String entityId) async => jsonDecode(
      (await (db.select(db.syncOperations)..where((t) => t.entityId.equals(entityId))).get()).last.payload,
    ) as Map<String, dynamic>;

/// `OK <status>` or the SQLSTATE the RPC raised.
Future<String> _call(String owner, Map<String, dynamic> payload) async {
  try {
    final result = await PsqlUploadGateway(owner).uploadSaleAggregate(payload) as Map;
    return 'OK ${result['status']}';
  } on ServerRejected catch (e) {
    return e.code ?? 'no code: ${e.message}';
  }
}

/// A queued sale payload re-cut to [quantity] (fresh ids, consistent totals),
/// as a crafted or older client could send it.
Map<String, dynamic> _recut(Map<String, dynamic> source, int quantity) {
  final p = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  final item = (p['sale_items'] as List).single as Map<String, dynamic>;
  final total = ((item['salePriceSnapshot'] as int) * quantity + 500) ~/ 1000;
  final saleId = _id();
  p['sale'] = {...p['sale'] as Map<String, dynamic>, 'id': saleId, 'subtotal': total, 'grandTotal': total};
  item..['id'] = _id()..['saleId'] = saleId..['quantity'] = quantity..['lineTotal'] = total;
  final movement = (p['inventory_movements'] as List).single as Map<String, dynamic>;
  movement..['id'] = _id()..['referenceId'] = saleId..['quantity'] = -quantity;
  final payment = (p['payments'] as List).single as Map<String, dynamic>;
  payment..['id'] = _id()..['saleId'] = saleId..['amount'] = total;
  p['audit_id'] = _id();
  return p;
}

Future<void> _drain(AppDatabase db, ShopFixture f) async {
  var clock = DateTime.now().toUtc();
  for (var i = 0; i < 2; i++) {
    await SyncWorker(
      queue: SyncQueueRepository(db, shopId: f.shopId),
      gateway: PsqlUploadGateway(f.ownerId),
      workerId: 'device-A',
      clock: () => clock,
    ).runOnce(limit: 50);
    clock = clock.add(const Duration(minutes: 6));
  }
}

Future<int> _serverStock(String product) =>
    serverScalar("select coalesce(sum(quantity),0) from inventory_movements where product_id=${_q(product)};");

/// A return payload exactly as LocalSaleReturnService writes it, with the
/// refund chosen by the test.
Map<String, dynamic> _returnPayload(ShopFixture f, String saleId, Map<String, Object?> item, int quantity, int refund) {
  final returnId = _id();
  return {
    'version': 1,
    'operation': 'sync_sale_return',
    'return': {
      'id': returnId, 'shop_id': f.shopId, 'original_sale_id': saleId, 'device_id': f.deviceA,
      'refund_method': 'cash', 'refund_amount': refund, 'reason': 'returned',
      'created_by': f.ownerId, 'created_at': DateTime.now().toUtc().toIso8601String(),
    },
    'items': [
      {
        'id': _id(), 'original_sale_item_id': item['id'], 'product_id': item['product_id'],
        'product_name_snapshot': item['name'], 'quantity': quantity,
        'unit_price_snapshot': item['price'], 'refund_amount': refund,
      },
    ],
    'inventory_movements': [
      {'id': _id(), 'product_id': item['product_id'], 'type': 'returnIn', 'quantity': quantity},
    ],
    'ledger_id': null,
    'audit_id': _id(),
  };
}

Future<Map<String, Object?>> _serverItem(String saleId) async {
  final raw = await psql("select json_build_object('id',id,'product_id',product_id,'name',product_name_snapshot,"
      "'price',sale_price_snapshot,'quantity',quantity,'line_total',line_total)::text from sale_items where sale_id=${_q(saleId)};");
  return (jsonDecode(raw) as Map).cast<String, Object?>();
}

void main() {
  group('U1 selling modes and sync', skip: !r1ServerEnabled, () {
    final f = ShopFixture();
    late AppDatabase db;
    late String atta;
    setUpAll(() async {
      await createScratchServer('units');
      await f.seedServer();
    });
    tearDownAll(dropScratchServer);
    setUp(() async {
      db = await f.openDevice();
      atta = await _addMeasured(f, db, 'Atta ${_id().substring(0, 4)}', _attaPrice);
    });
    tearDown(() => db.close());

    test('existing products default to piece', () async {
      expect(await psql("select string_agg(sell_mode||'/'||coalesce(family_id::text,'-')||'/'||"
          "coalesce(measure_presets::text,'-')||'/'||allow_custom_quantity,',' order by custom_name) "
          "from shop_products where id in (${_q(f.productId)},${_q(f.freeProductId)});"),
          'piece/-/-/true,piece/-/-/true');
    });

    test('piece 1000 and 2000 are accepted, 500 is refused with DPV01', () async {
      final sale = await _sell(db, f, f.productId, 1000, ShopFixture.salePrice);
      final payload = await _payloadOf(db, sale.saleId);
      expect(await _call(f.ownerId, payload), 'OK inserted');
      expect(await _call(f.ownerId, _recut(payload, 2000)), 'OK inserted');
      final half = _recut(payload, 500);
      expect(await _call(f.ownerId, half), 'DPV01');
      expect(await serverScalar("select count(*) from sales where id=${_q(half['sale']['id'] as String)};"), 0);
      expect(await psql("select measure_unit_snapshot is null from sale_items where sale_id=${_q(sale.saleId)};"), 't');
    });

    test('measured 250 / 750 / 1250 / 2500 g are accepted with exact totals and kg snapshot', () async {
      for (final (grams, paisa) in [(250, 3250), (750, 9750), (1250, 16250), (2500, 32500)]) {
        final sale = await _sell(db, f, atta, grams, _attaPrice);
        expect(await _call(f.ownerId, await _payloadOf(db, sale.saleId)), 'OK inserted');
        expect(await psql("select quantity||'/'||line_total||'/'||measure_unit_snapshot from sale_items where sale_id=${_q(sale.saleId)};"),
            '$grams/$paisa/kg');
      }
      expect(await _serverStock(atta), 40000 - 250 - 750 - 1250 - 2500);
    });

    test('a measure snapshot that does not match the product is refused', () async {
      final piece = await _payloadOf(db, (await _sell(db, f, f.productId, 1000, ShopFixture.salePrice)).saleId);
      ((piece['sale_items'] as List).single as Map)['measureUnitSnapshot'] = 'kg';
      expect(await _call(f.ownerId, piece), 'DPV01');
      final loose = await _payloadOf(db, (await _sell(db, f, atta, 500, _attaPrice)).saleId);
      ((loose['sale_items'] as List).single as Map)['measureUnitSnapshot'] = 'liter';
      expect(await _call(f.ownerId, loose), 'DPV01');
    });

    test('an old queued payload without measureUnitSnapshot still syncs and replays', () async {
      for (final (product, quantity, price, unit) in [
        (f.productId, 2000, ShopFixture.salePrice, 'null'),
        (atta, 750, _attaPrice, 'kg'),
      ]) {
        final sale = await _sell(db, f, product, quantity, price);
        final old = await _payloadOf(db, sale.saleId);
        ((old['sale_items'] as List).single as Map).remove('measureUnitSnapshot');
        expect(jsonEncode(old), isNot(contains('measureUnitSnapshot')));
        expect(await _call(f.ownerId, old), 'OK inserted');
        expect(await _call(f.ownerId, old), 'OK already_synced', reason: 'same frozen text replays');
        expect(await psql("select coalesce(measure_unit_snapshot,'null') from sale_items where sale_id=${_q(sale.saleId)};"),
            unit, reason: 'derived from the immutable selling mode');
        // The same sale id with different content is still a conflicting replay.
        expect(await _call(f.ownerId, await _payloadOf(db, sale.saleId)), 'DPC01');
      }
    });

    test('the real worker uploads a measured sale and its void restores exact grams', () async {
      final sale = await _sell(db, f, atta, 2500, _attaPrice);
      await _drain(db, f);
      expect(await _serverStock(atta), 37500);
      await LocalSaleVoidService(db, const UuidV7Generator()).voidSale(
        shopId: f.shopId, saleId: sale.saleId, ownerId: f.ownerId, deviceId: f.deviceA, reason: 'wrong bill');
      await _drain(db, f);
      expect(await serverScalar("select count(*) from sale_voids where original_sale_id=${_q(sale.saleId)};"), 1);
      expect(await _serverStock(atta), 40000, reason: 'void restores exactly 2500 g');
      expect(await localStock(db, atta), 40000);
      final queue = await (db.select(db.syncOperations)..where((t) => t.status.equalsValue(SyncStatus.synced).not())).get();
      expect(queue, isEmpty, reason: 'nothing left failed or in attention');
    });

    test('sell mode and a measured unit cannot change after creation', () async {
      await expectLater(psql("update shop_products set sell_mode='measured', unit='kg' where id=${_q(f.productId)};"),
          throwsA(isA<ServerRejected>().having((e) => e.message, 'message', contains('sell mode cannot change'))));
      await expectLater(psql("update shop_products set unit='liter' where id=${_q(atta)};"),
          throwsA(isA<ServerRejected>().having((e) => e.message, 'message', contains('measured unit cannot change'))));
      await expectLater(asOwner(f.ownerId, "update shop_products set sell_mode='measured' where id=${_q(f.productId)};"),
          throwsA(isA<ServerRejected>().having((e) => e.message, 'message', contains('permission denied'))));
      await expectLater(
          psql("insert into shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,sell_mode,created_at,updated_at) "
              "values(gen_random_uuid(),${_q(f.shopId)},'Bad','${f.categoryId}','piece',1,1,'measured',now(),now());"),
          throwsA(isA<ServerRejected>().having((e) => e.message, 'message', contains('shop_products_measured_unit'))));
      // Quick quantities stay owner-editable.
      await asOwner(f.ownerId, "update shop_products set measure_presets='{500,1000}', allow_custom_quantity=false where id=${_q(atta)};");
      expect(await psql("select measure_presets::text||allow_custom_quantity from shop_products where id=${_q(atta)};"), '{500,1000}false');
    });
  });

  group('U1 families, barcodes and product RPCs', skip: !r1ServerEnabled, () {
    final a = ShopFixture(), b = ShopFixture();
    setUpAll(() async {
      await createScratchServer('units_family');
      await a.seedServer();
      await b.seedServer();
    });
    tearDownAll(dropScratchServer);

    Future<String> create(ShopFixture f, Map<String, Object?> fields) async {
      final payload = jsonEncode({
        'shop_id': f.shopId, 'device_id': f.deviceA, 'product_id': _id(), 'movement_id': _id(),
        'category_id': f.categoryId, 'unit': 'piece', 'purchase_price': 100, 'sale_price': 200, ...fields,
      });
      return asOwner(f.ownerId, "select public.create_shop_product(\$P\$$payload\$P\$::jsonb)->>'product_id';");
    }

    Future<String> setFamily(ShopFixture f, String? family, List<String> products) => asOwner(f.ownerId,
        "select public.set_product_family(${_q(f.shopId)},${family == null ? 'null' : _q(family)},"
        "array[${products.map(_q).join(',')}]::uuid[])::text;");

    Matcher rejected(String text) => throwsA(isA<ServerRejected>().having((e) => e.message, 'message', contains(text)));

    test('create_shop_product creates measured and family products with their stock', () async {
      final family = _id();
      final loose = await create(a, {'name': 'Chawal', 'unit': 'kg', 'sell_mode': 'measured',
          'sale_price': 34000, 'opening_quantity': 25500, 'measure_presets': [250, 500, 1000, 5000], 'allow_custom_quantity': false});
      final pack250 = await create(a, {'name': 'Tapal Danedar', 'pack_label': '250 g', 'family_id': family, 'opening_quantity': 12000});
      final pack500 = await create(a, {'name': 'Tapal Danedar', 'pack_label': '500 g', 'family_id': family, 'opening_quantity': 6000});
      expect(await psql("select sell_mode||unit||measure_presets::text||allow_custom_quantity from shop_products where id=${_q(loose)};"),
          'measuredkg{250,500,1000,5000}false');
      expect(await _serverStock(loose), 25500);
      expect(await serverScalar("select count(*) from shop_products where family_id=${_q(family)} and shop_id=${_q(a.shopId)};"), 2);
      expect((await _serverStock(pack250), await _serverStock(pack500)), (12000, 6000), reason: 'independent stock');
    });

    test('create_shop_product refuses invalid selling setups', () async {
      await expectLater(create(a, {'name': 'X', 'opening_quantity': 1500}), rejected('piece stock must be whole units'));
      await expectLater(create(a, {'name': 'X', 'unit': 'piece', 'sell_mode': 'measured'}), rejected('unsupported unit'));
      await expectLater(create(a, {'name': 'X', 'measure_presets': [500]}), rejected('quick quantities are for measured products'));
      await expectLater(create(a, {'name': 'X', 'unit': 'kg', 'sell_mode': 'measured', 'measure_presets': [0]}),
          rejected('shop_products_measure_presets'));
      await expectLater(create(a, {'name': 'X', 'sell_mode': 'loose'}), rejected('unsupported sell mode'));
      await expectLater(create(b, {'name': 'X', 'shop_id': a.shopId}), rejected('owner access required'));
      // 'bag' (offered by the app) is now accepted on both product RPCs.
      expect(await create(a, {'name': 'Cement', 'unit': 'bag'}), isNotEmpty);
      final legacy = await asOwner(a.ownerId, "select public.create_custom_shop_product(${_q(a.shopId)},${_q(a.deviceA)},"
          "gen_random_uuid(),'Bag rice',${_q(a.categoryId)},null,'bag',null,null,1,2,0,0,gen_random_uuid())->>'status';");
      expect(legacy, 'inserted');
    });

    test('a retried create answers already_exists and writes nothing twice', () async {
      final id = _id(), movement = _id();
      final payload = jsonEncode({'shop_id': a.shopId, 'device_id': a.deviceA, 'product_id': id, 'movement_id': movement,
          'category_id': a.categoryId, 'unit': 'kg', 'sell_mode': 'measured', 'name': 'Sugar', 'purchase_price': 1,
          'sale_price': 2, 'opening_quantity': 5000});
      final call = "select public.create_shop_product(\$P\$$payload\$P\$::jsonb)->>'status';";
      expect(await asOwner(a.ownerId, call), 'inserted');
      expect(await asOwner(a.ownerId, call), 'already_exists');
      expect(await _serverStock(id), 5000);
    });

    test('a family cannot cross shops or be a sellable product', () async {
      final family = _id();
      final mine = await create(a, {'name': 'Lipton', 'pack_label': '95 g', 'family_id': family});
      final theirs = await create(b, {'name': 'Lipton', 'pack_label': '190 g'});
      await expectLater(setFamily(b, family, [theirs]), rejected('product family belongs to another shop'));
      await expectLater(setFamily(a, family, [theirs]), rejected('products must belong to the shop'));
      await expectLater(create(b, {'name': 'Lipton', 'family_id': family}), rejected('product family belongs to another shop'));
      await expectLater(
          asOwner(b.ownerId, "insert into shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,family_id,created_at,updated_at) "
              "values(gen_random_uuid(),${_q(b.shopId)},'Lipton',${_q(b.categoryId)},'piece',1,1,${_q(family)},now(),now());"),
          rejected('product family belongs to another shop'));
      await expectLater(setFamily(a, mine, [a.productId]), rejected('product family cannot be a sellable product'));
      await expectLater(asOwner(a.ownerId, "update shop_products set family_id=${_q(_id())} where id=${_q(mine)};"),
          rejected('permission denied'), reason: 'grouping only through the RPC');
      expect(await serverScalar("select count(*) from shop_products where family_id=${_q(family)};"), 1);
    });

    test('grouping existing products changes only family_id, never ids or stock', () async {
      final before = await psql("select string_agg(id||'/'||sell_mode||'/'||coalesce(unit,'')||'/'||"
          "(select coalesce(sum(quantity),0) from inventory_movements m where m.product_id=p.id),',' order by id) "
          "from shop_products p where id in (${_q(a.productId)},${_q(a.freeProductId)});");
      final family = _id();
      expect(await setFamily(a, family, [a.productId, a.freeProductId]), contains('"products": 2'));
      final after = await psql("select string_agg(id||'/'||sell_mode||'/'||coalesce(unit,'')||'/'||"
          "(select coalesce(sum(quantity),0) from inventory_movements m where m.product_id=p.id),',' order by id) "
          "from shop_products p where id in (${_q(a.productId)},${_q(a.freeProductId)});");
      expect(after, before);
      expect(await serverScalar("select count(*) from shop_products where family_id=${_q(family)};"), 2);
      await setFamily(a, null, [a.freeProductId]);
      expect(await serverScalar("select count(*) from shop_products where family_id=${_q(family)};"), 1);
    });

    test('barcodes are unique per shop across custom and master barcodes', () async {
      await create(a, {'name': 'Biscuit', 'barcode': '8964000000017'});
      await expectLater(create(a, {'name': 'Biscuit 2', 'barcode': '8964000000017'}), rejected('barcode already exists in shop'));
      await expectLater(
          asOwner(a.ownerId, "insert into shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,barcode,created_at,updated_at) "
              "values(gen_random_uuid(),${_q(a.shopId)},'Dup',${_q(a.categoryId)},'piece',1,1,'8964000000017',now(),now());"),
          rejected('shop_products_unique_barcode'));
      expect(await create(b, {'name': 'Biscuit', 'barcode': '8964000000017'}), isNotEmpty, reason: 'other shop may reuse it');

      // Master barcode against a custom barcode, both directions.
      final master = _id(), master2 = _id();
      await psql("insert into master_products(id,barcode,name,default_unit,created_at,updated_at) values"
          "(${_q(master)},'8964000000024','Catalog soap','piece',now(),now()),(${_q(master2)},'8964000000031','Catalog oil','piece',now(),now());");
      Future<String> addMaster(String id) => asOwner(a.ownerId, "select public.add_master_product_to_shop(${_q(a.shopId)},${_q(a.deviceA)},"
          "gen_random_uuid(),${_q(id)},1,2,0,0,gen_random_uuid())->>'status';");
      expect(await addMaster(master), 'inserted');
      await expectLater(create(a, {'name': 'Fake soap', 'barcode': '8964000000024'}), rejected('barcode already exists in shop'));
      await create(a, {'name': 'Loose oil label', 'barcode': '8964000000031'});
      await expectLater(addMaster(master2), rejected('barcode already exists in shop'));
    });
  });

  group('U1 cashier pull', skip: !r1ServerEnabled, () {
    final f = ShopFixture();
    setUpAll(() async {
      await createScratchServer('units_pull');
      await f.seedServer();
    });
    tearDownAll(dropScratchServer);

    test('device_pull includes the new product and sale-item fields', () async {
      final db = await f.openDevice();
      addTearDown(db.close);
      final atta = await _addMeasured(f, db, 'Atta', _attaPrice);
      final sale = await _sell(db, f, atta, 1250, _attaPrice);
      expect(await _call(f.ownerId, await _payloadOf(db, sale.saleId)), 'OK inserted');
      final raw = await psql('''
begin;
select set_config('request.jwt.claim.sub', ${_q(f.ownerId)}, true) is not null as ok0 \\gset
set local role authenticated;
select public.issue_device_credential(${_q(f.shopId)}, ${_q(f.deviceA)}) as secret \\gset
reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true) is not null as ok \\gset
select set_config('request.headers', json_build_object('x-dukaan-device', ${_q(f.deviceA)} || '.' || :'secret')::text, true) is not null as ok2 \\gset
select json_build_object('p', public.device_pull('shopProducts'), 'i', public.device_pull('saleItems'))::text;
commit;
''');
      final pulled = jsonDecode(raw) as Map<String, dynamic>;
      final products = {for (final p in pulled['p'] as List) (p as Map)['id']: p};
      expect(products[atta], containsPair('sell_mode', 'measured'));
      expect(products[atta], containsPair('measure_presets', [250, 500, 1000]));
      expect(products[atta], containsPair('allow_custom_quantity', true));
      expect(products[atta], containsPair('family_id', null));
      expect(products[f.productId], containsPair('sell_mode', 'piece'));
      final item = (pulled['i'] as List).cast<Map>().singleWhere((i) => i['sale_id'] == sale.saleId);
      expect((item['quantity'], item['line_total'], item['measure_unit_snapshot']), (1250, 16250, 'kg'));
    });
  });

  group('U1 cumulative partial returns on the server', skip: !r1ServerEnabled, () {
    final f = ShopFixture();
    late AppDatabase db;
    setUpAll(() async {
      await createScratchServer('units_returns');
      await f.seedServer();
      db = await f.openDevice();
    });
    tearDownAll(() async {
      await db.close();
      await dropScratchServer();
    });

    Future<Map<String, Object?>> soldLine(String product, int grams, int price) async {
      final sale = await _sell(db, f, product, grams, price);
      expect(await _call(f.ownerId, await _payloadOf(db, sale.saleId)), 'OK inserted');
      return {...await _serverItem(sale.saleId), 'sale': sale.saleId};
    }

    Future<String> giveBack(Map<String, Object?> line, int grams, int refund) =>
        _call(f.ownerId, _returnPayload(f, line['sale']! as String, line, grams, refund));

    Future<int> refunded(Map<String, Object?> line) =>
        serverScalar("select coalesce(sum(refund_amount),0) from sale_return_items where original_sale_item_id=${_q(line['id']! as String)};");

    test('333 g + 333 g + 334 g refund exactly the line total, never more', () async {
      final atta = await _addMeasured(f, db, 'Atta returns', _attaPrice);
      final line = await soldLine(atta, 1000, _attaPrice); // Rs 130.00
      // 13000*333/1000 = 4329; cumulative 666 -> 8658; remainder -> 13000.
      expect(await giveBack(line, 333, 4329), 'OK inserted');
      expect(await giveBack(line, 333, 4329), 'OK inserted', reason: 'second step: new and old formula agree here');
      expect(await giveBack(line, 334, 4343), 'DPV01', reason: 'a refund above the remainder (4342) is refused');
      expect(await giveBack(line, 334, 4342), 'OK inserted');
      expect(await refunded(line), 13000);
      expect(await giveBack(line, 1, 0), 'DPX01', reason: 'nothing left to return');
      expect(await _serverStock(atta), 40000, reason: 'exact grams restored');
    });

    test('Rs 13.33/kg dal: the old formula would over-refund 1 paisa; it cannot', () async {
      final dal = await _addMeasured(f, db, 'Dal', _dalPrice);
      final line = await soldLine(dal, 1500, _dalPrice);
      expect(line['line_total'], 2000);
      // Old formula: 667 + 667 + 667 = 2001 > 2000.
      expect(await giveBack(line, 500, 667), 'OK inserted', reason: 'first return: identical formulas');
      expect(await giveBack(line, 500, 667), 'OK inserted',
          reason: 'an old queued payload (per-return formula) is accepted while within the line total');
      expect(await giveBack(line, 500, 667), 'DPV01', reason: '2001 would exceed the line total');
      expect(await refunded(line), 1334);
      expect(await giveBack(line, 500, 666), 'OK inserted', reason: 'the final remainder');
      expect(await refunded(line), 2000);
    });

    test('667 g then 333 g with the new rule completes exactly', () async {
      final dal = await _addMeasured(f, db, 'Dal 2', _dalPrice);
      final line = await soldLine(dal, 1000, _dalPrice); // 1333
      // target(667) = (1333*667+500)/1000 = 889; remainder 444.
      expect(await giveBack(line, 667, 889), 'OK inserted');
      expect(await giveBack(line, 333, 445), 'DPV01', reason: 'would refund 1334 of 1333');
      expect(await giveBack(line, 333, 444), 'OK inserted');
      expect(await refunded(line), 1333);
    });

    test('piece 2000: return 1000 accepted; 500 refused; measured 2500: return 500 accepted', () async {
      final piece = await soldLine(f.productId, 2000, ShopFixture.salePrice); // Rs 360.00
      for (final quantity in [1, 250, 500, 1500]) {
        expect(await giveBack(piece, quantity, (36000 * quantity + 1000) ~/ 2000), 'DPV01', reason: '$quantity');
      }
      expect(await giveBack(piece, 1000, 18000), 'OK inserted');
      expect(await giveBack(piece, 1000, 18000), 'OK inserted');
      expect(await refunded(piece), 36000);
      expect(await giveBack(piece, 1000, 0), 'DPX01', reason: 'never beyond the sold quantity');

      final atta = await _addMeasured(f, db, 'Atta measured return', _attaPrice);
      final loose = await soldLine(atta, 2500, _attaPrice);
      expect(await giveBack(loose, 500, 6500), 'OK inserted');
      expect(await refunded(loose), 6500);
    });

    test('an old queued fractional piece return lands in attention, never refunded', () async {
      final piece = await soldLine(f.productId, 2000, ShopFixture.salePrice);
      final legacy = _returnPayload(f, piece['sale']! as String, piece, 500, 9000);
      final now = DateTime.now().toUtc();
      await db.into(db.syncOperations).insert(SyncOperationsCompanion.insert(
        id: _id(), shopId: f.shopId, deviceId: f.deviceA, entityType: 'sale_return',
        entityId: (legacy['return'] as Map)['id'] as String, operationType: SyncOperationType.create,
        payload: jsonEncode(legacy), createdAt: now, updatedAt: now,
      ));
      await _drain(db, f);
      final op = await (db.select(db.syncOperations)..where((t) => t.entityType.equals('sale_return'))).getSingle();
      expect((op.status, op.errorCode), (SyncStatus.needsAttention, 'DPV01'));
      expect(await refunded(piece), 0);
    });

    test('the same sale item twice in one return is refused', () async {
      final atta = await _addMeasured(f, db, 'Atta twice', _attaPrice);
      final line = await soldLine(atta, 2000, _attaPrice);
      final payload = _returnPayload(f, line['sale']! as String, line, 500, 6500);
      final item = (payload['items'] as List).single as Map<String, dynamic>;
      (payload['items'] as List).add({...item, 'id': _id()});
      (payload['inventory_movements'] as List).add({
        ...((payload['inventory_movements'] as List).single as Map<String, dynamic>), 'id': _id()});
      (payload['return'] as Map)['refund_amount'] = 13000;
      expect(await _call(f.ownerId, payload), 'DPV01');
      expect(await refunded(line), 0);
    });
  });

  group('U1 upgrade from the 22-migration schema', skip: !r1ServerEnabled, () {
    test('existing data upgrades in place; history is not rewritten', () async {
      await createScratchServer('units_upgrade', 22);
      addTearDown(dropScratchServer);
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      // A pre-U1 sale and partial return synced through the 22-migration server.
      final sale = await _sell(db, f, f.productId, 3000, ShopFixture.salePrice);
      expect(await _call(f.ownerId, await _payloadOf(db, sale.saleId)), 'OK inserted');
      final line = {...await _serverItem(sale.saleId), 'sale': sale.saleId};
      expect(await _call(f.ownerId, _returnPayload(f, sale.saleId, line, 1000, 18000)), 'OK inserted');
      const history = "select md5(string_agg(t::text, '|' order by t::text)) from ("
          "select row(s.*)::text t from sales s union all select row(i.*)::text from sale_items i "
          "union all select row(r.*)::text from sale_returns r union all select row(ri.*)::text from sale_return_items ri "
          "union all select row(m.*)::text from inventory_movements m) x;";
      final before = await psql(history);
      final productSeq = await psql("select string_agg(server_seq::text,',' order by id) from shop_products;");

      final migration = migrationFiles()[22];
      expect(migration.path, endsWith('202610080001_product_units_variants.sql'));
      await psql(migration.readAsStringSync());

      expect(await psql("select string_agg(distinct sell_mode||allow_custom_quantity,',') from shop_products;"), 'piecetrue');
      expect(await psql("select count(*) from sale_items where measure_unit_snapshot is not null;"), '0');
      expect(await psql("select string_agg(server_seq::text,',' order by id) from shop_products;"), productSeq,
          reason: 'adding columns does not renumber rows (no pull storm)');
      final after = await psql("select md5(string_agg(t::text, '|' order by t::text)) from ("
          "select row(s.*)::text t from sales s union all select row(i.id,i.shop_id,i.sale_id,i.product_id,i.product_name_snapshot,"
          "i.barcode_snapshot,i.quantity,i.cost_price_snapshot,i.sale_price_snapshot,i.discount_amount,i.line_total,i.created_at,i.server_seq)::text "
          "from sale_items i union all select row(r.*)::text from sale_returns r union all select row(ri.*)::text from sale_return_items ri "
          "union all select row(m.*)::text from inventory_movements m) x;");
      expect(after, before, reason: 'no historical financial row changed');

      // The upgraded server keeps accepting the old device's queued work.
      final next = await _sell(db, f, f.productId, 1000, ShopFixture.salePrice);
      expect(await _call(f.ownerId, await _payloadOf(db, next.saleId)), 'OK inserted');
      expect(await _call(f.ownerId, _returnPayload(f, sale.saleId, line, 1000, 18000)), 'OK inserted');
    });

    test('duplicate shop barcodes stop the migration atomically (read-only preflight)', () async {
      await createScratchServer('units_preflight', 22);
      addTearDown(dropScratchServer);
      final f = ShopFixture();
      await f.seedServer();
      await psql("update shop_products set barcode='8964000000048' where shop_id=${_q(f.shopId)};");
      final check = await psql(File('scripts/u1_duplicate_barcode_check.sql').readAsStringSync());
      expect(check, contains('8964000000048'), reason: 'the read-only check lists the duplicates');
      await expectLater(psql(migrationFiles()[22].readAsStringSync()),
          throwsA(isA<ServerRejected>().having((e) => e.message, 'message', contains('U1 preflight: 1 duplicate'))));
      expect(await psql("select count(*) from information_schema.columns where table_name='shop_products' and column_name='sell_mode';"),
          '0', reason: 'nothing applied');
      expect(await psql("select count(*) from shop_products where shop_id=${_q(f.shopId)} and barcode='8964000000048';"), '2',
          reason: 'no row deleted or merged');
    });
  });
}
