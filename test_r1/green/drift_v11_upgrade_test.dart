// R1.4 Drift v10 -> v11 upgrade (design §N): a real v10 database holding
// sales, stock, Udhaar, a pending and a failed outbox operation and legacy
// timestamp cursors is migrated in place. Every row and value survives, the
// legacy cursors are kept but carry no server position (so each entity is
// pulled again from the start once), and the schema equals a fresh v11.
@Tags(['r1-green'])
library;

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/generated_migrations/schema.dart';

const _t = 1790744400; // 2026-09-30T05:00:00Z in Drift's Unix seconds

const _v10Seed = '''
insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at)
  values('shop','Shop','','','trial','trial',$_t,$_t);
insert into shop_users(id,shop_id,user_id,role,created_at) values('m','shop','owner','owner',$_t);
insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at)
  values('device','shop','PC','windowsDesktop','d',$_t,$_t);
insert into shop_products(id,shop_id,custom_name,purchase_price,sale_price,created_at,updated_at)
  values('coke','shop','Coke',15000,18000,$_t,$_t),('rice','shop','Rice',10000,12000,$_t,$_t);
insert into customers(id,shop_id,name,credit_limit,created_at,updated_at) values('c','shop','Ahmed',100000,$_t,$_t);
insert into inventory_movements(id,shop_id,product_id,type,quantity,created_by,created_at)
  values('open-coke','shop','coke','openingStock',10000,'owner',$_t),('open-rice','shop','rice','openingStock',10000,'owner',$_t);
insert into sales(id,shop_id,cashier_id,customer_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at)
  values('S1','shop','owner','c','device',30000,0,0,30000,'paid','completed',$_t),
        ('S2','shop','owner',null,'device',18000,0,0,18000,'paid','completed',$_t);
insert into sale_items(id,shop_id,sale_id,product_id,product_name_snapshot,quantity,cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at)
  values('S1-1','shop','S1','coke','Coke',1000,15000,18000,0,18000,$_t),
        ('S1-2','shop','S1','rice','Rice',1000,10000,12000,0,12000,$_t),
        ('S2-1','shop','S2','coke','Coke',1000,15000,18000,0,18000,$_t);
insert into sale_payments(id,shop_id,sale_id,payment_method,amount,created_at)
  values('S1-p','shop','S1','credit',30000,$_t),('S2-p','shop','S2','cash',18000,$_t);
insert into inventory_movements(id,shop_id,product_id,type,quantity,reference_type,reference_id,created_by,created_at)
  values('S1-m1','shop','coke','sale',-1000,'sale','S1','owner',$_t),
        ('S1-m2','shop','rice','sale',-1000,'sale','S1','owner',$_t),
        ('S2-m1','shop','coke','sale',-1000,'sale','S2','owner',$_t);
insert into customer_ledger_entries(id,shop_id,customer_id,type,amount,sale_id,created_by,created_at)
  values('S1-l','shop','c','creditSale',30000,'S1','owner',$_t);
insert into sync_operations(id,shop_id,device_id,entity_type,entity_id,operation_type,payload,status,retry_count,created_at,updated_at)
  values('op-S1','shop','device','sale_aggregate','S1','create','{"sale":"S1"}','pending',0,$_t,$_t);
insert into sync_operations(id,shop_id,device_id,entity_type,entity_id,operation_type,payload,status,retry_count,last_error,next_attempt_at,created_at,updated_at)
  values('op-S2','shop','device','sale_aggregate','S2','create','{"sale":"S2"}','failed',3,'network down',${_t + 600},$_t,$_t);
insert into sync_cursors(shop_id,entity_type,updated_at,entity_id) values('shop','inventoryMovements',$_t,'S2-m1'),('shop','sales',$_t,'S2');
''';

/// Records the cursor each fetch receives.
final class _Recorder implements ReferencePullGateway {
  final afters = <PullCursor?>[];
  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    afters.add(after);
    return const [];
  }
}

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v10 -> v11 keeps every sale, stock, Udhaar, outbox and cursor row', () async {
    final schema = await verifier.schemaAt(10);
    schema.rawDatabase.execute(_v10Seed);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 11);

    expect((await db.select(db.sales).get()).map((s) => (s.id, s.grandTotal, s.customerId)).toSet(),
        {('S1', 30000, 'c'), ('S2', 18000, null)});
    expect(await db.select(db.saleItems).get(), hasLength(3));
    expect((await db.select(db.salePayments).get()).map((p) => (p.id, p.paymentMethod, p.amount)).toSet(),
        {('S1-p', PaymentMethod.credit, 30000), ('S2-p', PaymentMethod.cash, 18000)});
    Future<int> scalar(String sql) async => (await db.customSelect(sql).getSingle()).read<int>('v');
    expect(await scalar("select sum(quantity) v from inventory_movements where product_id='coke'"), 8000);
    expect(await scalar("select sum(quantity) v from inventory_movements where product_id='rice'"), 9000);
    expect(await scalar("select sum(amount) v from customer_ledger_entries where customer_id='c'"), 30000);
    final ops = {for (final o in await db.select(db.syncOperations).get()) o.id: o};
    expect(ops['op-S1']!.status, SyncStatus.pending);
    expect((ops['op-S2']!.status, ops['op-S2']!.retryCount, ops['op-S2']!.lastError),
        (SyncStatus.failed, 3, 'network down'));
    expect(ops['op-S2']!.nextAttemptAt!.millisecondsSinceEpoch ~/ 1000, _t + 600);
    expect(ops['op-S1']!.payload, '{"sale":"S1"}');

    final cursors = await db.select(db.syncCursors).get();
    expect(cursors.map((c) => (c.entityType, c.entityId, c.serverSeq)).toSet(),
        {('inventoryMovements', 'S2-m1', null), ('sales', 'S2', null)});

    // A legacy cursor is not a safe position: the first pull starts over.
    final recorder = _Recorder();
    await ReferencePullService(db, recorder, shopId: 'shop').pull(PullEntity.sales);
    expect(recorder.afters, [null]);
  });

  test('a fresh v11 install has exactly the v11 schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 11);
    await db.validateDatabaseSchema();
  });
}
