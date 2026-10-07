// U1 Drift v12 -> v13 upgrade: a real v12 tablet database holding products,
// a sale, a queued (frozen) sale payload and pull cursors for several
// entities is migrated in place. Every product becomes a piece product, every
// sale line a count, the queued payload is untouched, and only the
// shopProducts and saleItems cursors lose their position, so exactly those
// two entities are pulled again from the start and receive the new fields.
@Tags(['r1-green'])
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/generated_migrations/schema.dart';

const _t = 1791435600; // 2026-10-08T05:00:00Z in Drift's Unix seconds
const _payload =
    '{"version":1,"operation":"sync_sale_transaction","sale_items":[{"id":"S1-i","quantity":2000}]}';

const _v12Seed = '''
insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at)
  values('shop','Shop','','','trial','trial',$_t,$_t);
insert into shop_users(id,shop_id,user_id,role,created_at) values('m','shop','owner','owner',$_t);
insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at)
  values('device','shop','Tablet','androidTablet','d',$_t,$_t);
insert into shop_products(id,shop_id,custom_name,unit,pack_label,purchase_price,sale_price,created_at,updated_at)
  values('coke','shop','Coke','piece',null,15000,18000,$_t,$_t),
        ('atta','shop','Atta','kg','10 kg bag',60000,72000,$_t,$_t);
insert into sales(id,shop_id,cashier_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at)
  values('S1','shop','owner','device',36000,0,0,36000,'paid','completed',$_t);
insert into sale_items(id,shop_id,sale_id,product_id,product_name_snapshot,quantity,cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at)
  values('S1-i','shop','S1','coke','Coke',2000,15000,18000,0,36000,$_t);
insert into sync_operations(id,shop_id,device_id,entity_type,entity_id,operation_type,payload,status,retry_count,created_at,updated_at)
  values('op-S1','shop','device','sale_aggregate','S1','create','$_payload','pending',0,$_t,$_t);
insert into sync_cursors(shop_id,entity_type,updated_at,entity_id,server_seq) values
  ('shop','shopProducts',$_t,'atta',7),
  ('shop','saleItems',$_t,'S1-i',9),
  ('shop','sales',$_t,'S1',9),
  ('shop','inventoryMovements',$_t,'m1',8),
  ('shop','customers',$_t,'c1',3);
''';

/// Serves one page per entity from a fixed server state, recording the
/// cursor each request carried.
final class _FakeServer implements ReferencePullGateway {
  _FakeServer(this.rows);
  final Map<PullEntity, List<Map<String, dynamic>>> rows;
  final requests = <PullEntity, PullCursor?>{};

  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    requests[entity] = after;
    return [
      for (final r in rows[entity] ?? const <Map<String, dynamic>>[])
        if (after == null || (r['server_seq'] as int) > after.serverSeq)
          RemoteChange(
            entity: entity,
            id: r['id'] as String,
            shopId: 'shop',
            updatedAt: DateTime.utc(2026, 10, 8),
            serverSeq: r['server_seq'] as int,
            data: r,
          ),
    ];
  }
}

Map<String, dynamic> _product(String id, String name, String unit, {String mode = 'piece', List<int>? presets, int seq = 7}) => {
      'id': id, 'shop_id': 'shop', 'master_product_id': null, 'custom_name': name, 'barcode': null,
      'category_id': null, 'unit': unit, 'pack_label': null, 'image_path': null,
      'purchase_price': 15000, 'sale_price': 18000, 'stock_tracking_enabled': true,
      'low_stock_level': null, 'is_active': true, 'created_at': '2026-10-08T05:00:00Z',
      'updated_at': '2026-10-08T05:00:00Z', 'sell_mode': mode, 'family_id': null,
      'measure_presets': presets, 'allow_custom_quantity': true, 'server_seq': seq,
    };

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  Future<AppDatabase> upgraded() async {
    final schema = await verifier.schemaAt(12);
    schema.rawDatabase.execute(_v12Seed);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
    return db;
  }

  test('v12 -> v13 keeps every row; products become piece, lines counts', () async {
    final db = await upgraded();
    final products = {for (final p in await db.select(db.shopProducts).get()) p.id: p};
    expect(products.keys.toSet(), {'coke', 'atta'});
    for (final p in products.values) {
      expect((p.sellMode, p.familyId, p.measurePresets, p.allowCustomQuantity),
          (SellMode.piece.name, null, null, true), reason: p.id);
    }
    expect(products['atta']!.unit, 'kg', reason: 'a kg-labelled product stays a piece product');
    final item = await db.select(db.saleItems).getSingle();
    expect((item.quantity, item.lineTotal, item.measureUnitSnapshot), (2000, 36000, null));
    final op = await db.select(db.syncOperations).getSingle();
    expect((op.status, op.payload), (SyncStatus.pending, _payload), reason: 'queued payload frozen');
  });

  test('only the shopProducts and saleItems cursors lose their position', () async {
    final db = await upgraded();
    final cursors = {for (final c in await db.select(db.syncCursors).get()) c.entityType: c.serverSeq};
    expect(cursors, {
      'shopProducts': null,
      'saleItems': null,
      'sales': 9,
      'inventoryMovements': 8,
      'customers': 3,
    });
  });

  test('the reset cursors re-pull from the start and deliver the new fields', () async {
    final db = await upgraded();
    final server = _FakeServer({
      PullEntity.shopProducts: [
        _product('coke', 'Coke', 'piece', seq: 2),
        _product('loose-atta', 'Atta loose', 'kg', mode: 'measured', presets: [250, 500, 1000], seq: 7),
      ],
      PullEntity.saleItems: [
        {
          'id': 'S1-i', 'shop_id': 'shop', 'sale_id': 'S1', 'product_id': 'coke',
          'product_name_snapshot': 'Coke', 'barcode_snapshot': null, 'quantity': 2000,
          'cost_price_snapshot': 15000, 'sale_price_snapshot': 18000, 'discount_amount': 0,
          'line_total': 36000, 'created_at': '2026-10-08T05:00:00Z',
          'measure_unit_snapshot': null, 'server_seq': 9,
        },
      ],
      PullEntity.sales: [
        {'id': 'S-new', 'server_seq': 5},
      ],
    });
    final pull = ReferencePullService(db, server, shopId: 'shop');
    expect(await pull.pull(PullEntity.shopProducts), 2);
    expect(server.requests[PullEntity.shopProducts], isNull, reason: 'pulled from the start');
    expect(await pull.pull(PullEntity.saleItems), 1);
    expect(server.requests[PullEntity.saleItems], isNull);
    expect(await pull.pull(PullEntity.sales), 0, reason: 'an unrelated cursor keeps its position');
    expect(server.requests[PullEntity.sales]!.serverSeq, 9);

    final loose = await (db.select(db.shopProducts)..where((t) => t.id.equals('loose-atta'))).getSingle();
    expect((loose.sellMode, loose.unit, loose.measurePresets), ('measured', 'kg', '[250,500,1000]'));
    final cursors = {for (final c in await db.select(db.syncCursors).get()) c.entityType: c.serverSeq};
    expect((cursors['shopProducts'], cursors['saleItems']), (7, 9));
  });

  test('a fresh v13 install has exactly the v13 schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 13);
    await db.validateDatabaseSchema();
    await db.into(db.shops).insert(ShopsCompanion.insert(
      id: 'shop', name: 'S', phone: '', address: '',
      subscriptionPlan: SubscriptionPlan.trial, subscriptionStatus: SubscriptionStatus.trial,
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
    ));
    await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
      id: 'p', shopId: 'shop', customName: const Value('P'), purchasePrice: 1, salePrice: 2,
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
    ));
    expect((await db.select(db.shopProducts).getSingle()).sellMode, 'piece');
  });
}
