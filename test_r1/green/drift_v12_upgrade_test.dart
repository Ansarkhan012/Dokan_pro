// R1.5 Drift v11 -> v12 upgrade: a real v11 tablet database holding a sale, an
// Udhaar sale and pending, retry-wait (failed) and synced outbox operations is
// migrated in place. Every row and status survives, the new failure columns
// start empty, and the schema equals a fresh v12 install.
@Tags(['r1-green'])
library;

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/generated_migrations/schema.dart';

const _t = 1790830800; // 2026-10-01T05:00:00Z in Drift's Unix seconds

const _v11Seed = '''
insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at)
  values('shop','Shop','','','trial','trial',$_t,$_t);
insert into shop_users(id,shop_id,user_id,role,created_at) values('m','shop','owner','owner',$_t);
insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at)
  values('device','shop','Tablet','androidTablet','d',$_t,$_t);
insert into shop_products(id,shop_id,custom_name,purchase_price,sale_price,created_at,updated_at)
  values('coke','shop','Coke',15000,18000,$_t,$_t);
insert into customers(id,shop_id,name,credit_limit,created_at,updated_at) values('c','shop','Ahmed',100000,$_t,$_t);
insert into sales(id,shop_id,cashier_id,customer_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at)
  values('S1','shop','owner','c','device',18000,0,0,18000,'paid','completed',$_t),
        ('S2','shop','owner',null,'device',18000,0,0,18000,'paid','completed',$_t),
        ('S3','shop','owner',null,'device',18000,0,0,18000,'paid','completed',$_t);
insert into customer_ledger_entries(id,shop_id,customer_id,type,amount,sale_id,created_by,created_at)
  values('S1-l','shop','c','creditSale',18000,'S1','owner',$_t);
insert into sync_operations(id,shop_id,device_id,entity_type,entity_id,operation_type,payload,status,retry_count,created_at,updated_at)
  values('op-S1','shop','device','sale_aggregate','S1','create','{"sale":"S1"}','pending',0,$_t,$_t);
insert into sync_operations(id,shop_id,device_id,entity_type,entity_id,operation_type,payload,status,retry_count,last_error,next_attempt_at,created_at,updated_at)
  values('op-S2','shop','device','sale_aggregate','S2','create','{"sale":"S2"}','failed',4,'network down',${_t + 600},$_t,$_t);
insert into sync_operations(id,shop_id,device_id,entity_type,entity_id,operation_type,payload,status,retry_count,synced_at,created_at,updated_at)
  values('op-S3','shop','device','sale_aggregate','S3','create','{"sale":"S3"}','synced',0,$_t,$_t,$_t);
''';

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v11 -> v12 keeps every sale, Udhaar and outbox row and status', () async {
    final schema = await verifier.schemaAt(11);
    schema.rawDatabase.execute(_v11Seed);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 12);

    expect((await db.select(db.sales).get()).map((s) => s.id).toSet(), {'S1', 'S2', 'S3'});
    expect((await db.select(db.customerLedgerEntries).getSingle()).amount, 18000);
    final ops = {for (final o in await db.select(db.syncOperations).get()) o.id: o};
    expect(ops['op-S1']!.status, SyncStatus.pending);
    expect((ops['op-S2']!.status, ops['op-S2']!.retryCount, ops['op-S2']!.lastError),
        (SyncStatus.failed, 4, 'network down'), reason: 'retry-wait keeps its backoff state');
    expect(ops['op-S2']!.nextAttemptAt!.millisecondsSinceEpoch ~/ 1000, _t + 600);
    expect(ops['op-S3']!.status, SyncStatus.synced);
    for (final op in ops.values) {
      expect((op.errorClass, op.errorCode, op.attentionReason, op.attentionAt,
              op.firstErrorAt, op.unknownErrorCount, op.acknowledgedAt),
          (null, null, null, null, null, 0, null), reason: op.id);
    }
    expect(await SyncQueueRepository(db, shopId: 'shop').attention(), isEmpty,
        reason: 'an upgrade alone never raises attention');
    expect(ops['op-S1']!.payload, '{"sale":"S1"}');
  });

  test('a fresh v12 install has exactly the v12 schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 12);
    await db.validateDatabaseSchema();
  });
}
