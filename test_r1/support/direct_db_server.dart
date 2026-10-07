// R1 direct-database harness (fast layer). NOT production code.
//
// Client side: real Drift services on independent in-memory databases, one per
// simulated device.
// Server side: the real migrated PostgreSQL functions, RLS and triggers in a
// disposable scratch database inside the local Supabase Docker container.
// RPCs and pull queries execute as the `authenticated` role with the owner's
// JWT `sub` claim, exactly as PostgREST would set them. Only the HTTP hop
// (PostgREST/Kong) is not exercised.
//
// Enabled only with --dart-define=R1_SERVER=true because it needs Docker.
// Every test file uses its own scratch database (`createScratchServer('<name>')` → `r1_direct_<name>`) so
// files can run in parallel without interfering, and the database is dropped
// in tearDownAll. The dev database (`postgres`) is never written.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_failure.dart';
import 'package:uuid/uuid.dart';

const r1ServerEnabled = bool.fromEnvironment('R1_SERVER');
const _container = 'supabase_db_POS_store';
/// Scratch database of the current test isolate (one per test file).
String scratchDb = 'r1_direct';

/// Thrown when PostgreSQL rejects a statement; mirrors a PostgREST error.
/// [code] is the SQLSTATE when the caller captured it (PsqlUploadGateway).
final class ServerRejected implements Exception, SyncCodedError {
  ServerRejected(this.message, {this.code});
  final String message;
  @override
  final String? code;
  @override
  String toString() =>
      'ServerRejected: ${code == null ? '' : '[$code] '}$message';
}

Future<String> psql(String script, {String? db}) async {
  final process = await Process.start('docker', [
    'exec', '-i', _container, 'psql', '-X', '-q', '-At',
    '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', db ?? scratchDb,
  ]);
  process.stdin.write(script);
  await process.stdin.close();
  // Drain both streams together: an error with a long CONTEXT (a whole
  // failing INSERT) can fill the stderr pipe, and docker exec then never
  // closes stdout while stderr is unread.
  final streams = await Future.wait([
    process.stdout.transform(utf8.decoder).join(),
    process.stderr.transform(utf8.decoder).join(),
  ]);
  final out = streams[0], err = streams[1];
  if (await process.exitCode != 0) {
    final line = err.split('\n').firstWhere(
      (l) => l.contains('ERROR'),
      orElse: () => err.trim(),
    );
    throw ServerRejected(line.replaceFirst(RegExp(r'^.*ERROR:\s*'), ''));
  }
  return out.trim();
}

/// Repository migrations in application order.
List<File> migrationFiles() => Directory('supabase/migrations')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.sql'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Creates the scratch database from zero with every repository migration, or
/// only the first [upTo] of them (to test an upgrade).
Future<void> createScratchServer([String? name, int? upTo]) async {
  if (name != null) scratchDb = 'r1_direct_$name';
  if (!RegExp(r'^r1_direct(_[a-z0-9_]+)?$').hasMatch(scratchDb)) {
    throw StateError('refusing unexpected scratch database name $scratchDb');
  }
  await psql('drop database if exists $scratchDb;', db: 'postgres');
  await psql('create database $scratchDb;', db: 'postgres');
  await psql(r'''
create schema auth;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(nullif(current_setting('request.jwt.claim.sub', true),''),
    (nullif(current_setting('request.jwt.claims', true),'')::jsonb->>'sub')),'')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
''');
  final migrations = migrationFiles();
  for (final file in upTo == null ? migrations : migrations.take(upTo)) {
    await psql(file.readAsStringSync());
  }
}

Future<void> dropScratchServer() =>
    psql('drop database if exists $scratchDb with (force);', db: 'postgres');

String _q(String value) => "'${value.replaceAll("'", "''")}'";

/// Runs [sql] inside a transaction as `authenticated` with [ownerId] as sub.
Future<String> asOwner(String ownerId, String sql) => psql('''
begin;
do \$\$ begin perform set_config('request.jwt.claim.sub', ${_q(ownerId)}, true); end \$\$;
set local role authenticated;
$sql
commit;
''');

/// Same RPC routing as SupabaseSaleUploadGateway, executed in PostgreSQL.
final class PsqlUploadGateway implements SaleUploadGateway {
  PsqlUploadGateway(this.ownerId);
  final String ownerId;
  final calls = <String>[];

  /// Returns the RPC's JSON result; a rejection throws [ServerRejected] with
  /// the SQLSTATE, as PostgREST reports it in `PostgrestException.code`.
  @override
  Future<Object?> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) async {
    final operation = payload['operation'];
    final rpc = switch (operation) {
      'sync_customer_payment' => 'sync_customer_payment',
      'sync_purchase_transaction' => 'sync_purchase_transaction',
      'sync_supplier_payment' => 'sync_supplier_payment',
      'sync_expense' => 'sync_expense',
      'sync_inventory_adjustment' => 'sync_inventory_adjustment',
      'sync_sale_return' => 'sync_sale_return',
      'sync_sale_void' => 'sync_sale_void',
      _ => 'sync_sale_transaction',
    };
    final body = jsonEncode(payloadForCloud(payload));
    final token = cashierSessionToken == null ? 'null' : _q(cashierSessionToken);
    final result = await asOwner(ownerId, '''
create temp table if not exists r1_upload(v text) on commit drop;
do \$do\$ begin
  insert into r1_upload select public.$rpc(\$R1\$$body\$R1\$::jsonb, $token)::text;
exception when others then insert into r1_upload values ('ERR ' || sqlstate || ' ' || sqlerrm);
end \$do\$;
select v from r1_upload;
''');
    calls.add('$rpc -> $result');
    if (result.startsWith('ERR ')) {
      throw ServerRejected(result.substring(10), code: result.substring(4, 9));
    }
    return jsonDecode(result);
  }
}

/// Same query shape as SupabaseReferencePullGateway, executed under RLS.
final class PsqlPullGateway implements ReferencePullGateway {
  PsqlPullGateway(this.ownerId);
  final String ownerId;

  static const _createdAtEntities = {
    PullEntity.inventoryMovements,
    PullEntity.customerLedgerEntries,
    PullEntity.supplierLedgerEntries,
    PullEntity.purchases,
    PullEntity.purchaseItems,
    PullEntity.purchasePayments,
    PullEntity.expenses,
    PullEntity.sales,
    PullEntity.saleItems,
    PullEntity.salePayments,
    PullEntity.saleReturns,
    PullEntity.saleReturnItems,
    PullEntity.saleVoids,
  };

  static String table(PullEntity e) => switch (e) {
    PullEntity.shops => 'shops',
    PullEntity.devices => 'devices',
    PullEntity.cashiers => 'cashiers',
    PullEntity.categories || PullEntity.globalCategories => 'categories',
    PullEntity.masterProducts => 'master_products',
    PullEntity.shopProducts => 'shop_products',
    PullEntity.customers => 'customers',
    PullEntity.customerLedgerEntries => 'customer_ledger_entries',
    PullEntity.suppliers => 'suppliers',
    PullEntity.supplierLedgerEntries => 'supplier_ledger_entries',
    PullEntity.purchases => 'purchases',
    PullEntity.purchaseItems => 'purchase_items',
    PullEntity.purchasePayments => 'purchase_payments',
    PullEntity.expenseCategories => 'expense_categories',
    PullEntity.expenses => 'expenses',
    PullEntity.inventoryMovements => 'inventory_movements',
    PullEntity.sales => 'sales',
    PullEntity.saleItems => 'sale_items',
    PullEntity.salePayments => 'sale_payments',
    PullEntity.saleReturns => 'sale_returns',
    PullEntity.saleReturnItems => 'sale_return_items',
    PullEntity.saleVoids => 'sale_voids',
  };

  /// Same scope, cursor and order as SupabaseReferencePullGateway (R1.4).
  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    final column = _createdAtEntities.contains(entity) ? 'created_at' : 'updated_at';
    final scope = switch (entity) {
      PullEntity.shops => 'id = ${_q(shopId)}::uuid',
      PullEntity.globalCategories => 'shop_id is null',
      PullEntity.masterProducts => 'true',
      _ => 'shop_id = ${_q(shopId)}::uuid',
    };
    final columns = entity == PullEntity.cashiers
        ? 'id,shop_id,display_name,login_code,credential_version,is_active,created_at,updated_at,server_seq'
        : '*';
    final cursor = after == null || after.serverSeq < 0
        ? ''
        : after.entityId.isEmpty
            ? 'and server_seq > ${after.serverSeq}'
            : 'and (server_seq > ${after.serverSeq} or '
                '(server_seq = ${after.serverSeq} and id > ${_q(after.entityId)}::uuid))';
    final raw = await asOwner(
      ownerId,
      "select coalesce(json_agg(t), '[]') from (select $columns from public.${table(entity)} "
      'where $scope $cursor order by server_seq, id limit $limit) t;',
    );
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return [
      for (final row in rows)
        RemoteChange(
          entity: entity,
          id: row['id'] as String,
          shopId: row['shop_id'] as String?,
          updatedAt: DateTime.parse(row[column] as String).toUtc(),
          serverSeq: (row['server_seq'] as num).toInt(),
          data: row,
        ),
    ];
  }
}

/// One shop's identities shared by the server and every simulated device.
final class ShopFixture {
  ShopFixture()
    : shopId = _id(),
      ownerId = _id(),
      categoryId = _id(),
      productId = _id(),
      freeProductId = _id(),
      customerId = _id(),
      openingMovementId = _id(),
      deviceA = _id(),
      deviceB = _id();
  static String _id() => const Uuid().v4();

  final String shopId, ownerId, categoryId, productId, freeProductId,
      customerId, openingMovementId, deviceA, deviceB;
  static const salePrice = 18000; // Rs 180.00
  static const openingStock = 10000; // 10 units
  final seededAt = DateTime.utc(2026, 1, 1);

  /// Server rows, inserted as the database owner (like the app's RPC setup).
  Future<void> seedServer({int? creditLimit}) => psql('''
insert into auth.users(id,email) values(${_q(ownerId)}, ${_q('$ownerId@r1.test')});
insert into public.shops(id,name) values(${_q(shopId)},'R1 shop');
insert into public.shop_users(shop_id,user_id,role) values(${_q(shopId)},${_q(ownerId)},'owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
  (${_q(deviceA)},${_q(shopId)},'A','androidTablet',gen_random_uuid()),
  (${_q(deviceB)},${_q(shopId)},'B','androidTablet',gen_random_uuid());
insert into public.categories(id,shop_id,name,created_at,updated_at) values(${_q(categoryId)},${_q(shopId)},'C',now(),now());
insert into public.shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,created_at,updated_at) values
  (${_q(productId)},${_q(shopId)},'Coke',${_q(categoryId)},'piece',15000,$salePrice,now(),now()),
  (${_q(freeProductId)},${_q(shopId)},'Free bag',${_q(categoryId)},'piece',0,0,now(),now());
insert into public.customers(id,shop_id,name,credit_limit,created_at,updated_at) values
  (${_q(customerId)},${_q(shopId)},'Ahmed',${creditLimit ?? 'null'},now(),now());
insert into public.inventory_movements(id,shop_id,product_id,type,quantity,reference_type,created_by,device_id,created_at) values
  (${_q(openingMovementId)},${_q(shopId)},${_q(productId)},'openingStock',$openingStock,'product_setup',${_q(ownerId)},${_q(deviceA)},'2026-01-01T00:00:00Z');
''');

  /// A device database seeded with the same reference data the pull provides.
  /// [file] makes it file-backed, so a restart is close + reopen.
  Future<AppDatabase> openDevice({int? creditLimit, File? file}) async {
    final db = AppDatabase(file == null ? NativeDatabase.memory() : NativeDatabase(file));
    await db.into(db.shops).insert(ShopsCompanion.insert(
      id: shopId, name: 'R1 shop', phone: '', address: '',
      subscriptionPlan: SubscriptionPlan.trial,
      subscriptionStatus: SubscriptionStatus.trial,
      createdAt: seededAt, updatedAt: seededAt,
    ));
    await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
      id: _id(), shopId: shopId, userId: ownerId, role: ShopRole.owner,
      createdAt: seededAt,
    ));
    for (final device in [deviceA, deviceB]) {
      await db.into(db.devices).insert(DevicesCompanion.insert(
        id: device, shopId: shopId, deviceName: device,
        deviceType: DeviceType.androidTablet, deviceIdentifier: device,
        createdAt: seededAt,
      ));
    }
    for (final (id, name, price) in [
      (productId, 'Coke', salePrice),
      (freeProductId, 'Free bag', 0),
    ]) {
      await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
        id: id, shopId: shopId, customName: Value(name),
        purchasePrice: price == 0 ? 0 : 15000, salePrice: price,
        createdAt: seededAt, updatedAt: seededAt,
      ));
    }
    await db.into(db.customers).insert(CustomersCompanion.insert(
      id: customerId, shopId: shopId, name: 'Ahmed',
      creditLimit: Value(creditLimit), createdAt: seededAt, updatedAt: seededAt,
    ));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
      id: openingMovementId, shopId: shopId, productId: productId,
      type: InventoryMovementType.openingStock, quantity: openingStock,
      referenceType: const Value('product_setup'), createdBy: ownerId,
      deviceId: Value(deviceA), createdAt: DateTime.utc(2026, 1, 1),
    ));
    return db;
  }
}

Future<int> localStock(AppDatabase db, String productId) async => (await db
        .customSelect(
          'select coalesce(sum(quantity),0) q from inventory_movements where product_id=?',
          variables: [Variable(productId)],
        )
        .getSingle())
    .read<int>('q');

Future<int> localBalance(AppDatabase db, String customerId) async => (await db
        .customSelect(
          "select coalesce(sum(case when type in ('openingBalance','creditSale','adjustment') "
          "then amount else -amount end),0) b from customer_ledger_entries where customer_id=?",
          variables: [Variable(customerId)],
        )
        .getSingle())
    .read<int>('b');

Future<int> serverScalar(String sql) async => int.parse(await psql(sql));
