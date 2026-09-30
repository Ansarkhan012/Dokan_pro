// R1.3 upgrade path: a database at the approved R1.2 schema (first 18
// migrations) holding a void accepted under the old v1 contract is upgraded
// with the R1.3 migration. History is preserved byte for byte (never replayed
// or repaired), v1 is refused from then on, and v2 works.
@Tags(['r1-direct-db'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/direct_db_server.dart';

const _r12MigrationCount = 18;

Future<String> _callVoid(String actor, Map<String, dynamic> payload) => asOwner(actor, '''
create temp table if not exists r1_out(v text) on commit drop;
do \$do\$ begin
  insert into r1_out select public.sync_sale_void(\$R1\$${jsonEncode(payload)}\$R1\$::jsonb, null)::text;
exception when others then insert into r1_out values (sqlstate || ' ' || sqlerrm);
end \$do\$;
select v from r1_out;
''');

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('void_upgrade', _r12MigrationCount);
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });

  test('upgrade from the R1.2 schema preserves a v1 void and then refuses v1 and accepts v2', () async {
    expect(migrationFiles(), hasLength(_r12MigrationCount + 1), reason: 'R1.3 adds exactly one migration');
    final f = ShopFixture();
    await f.seedServer();
    final db = await f.openDevice();
    addTearDown(db.close);
    Future<void> upload() => SyncWorker(
          queue: SyncQueueRepository(db, shopId: f.shopId),
          gateway: PsqlUploadGateway(f.ownerId),
          workerId: 'device-A',
        ).runOnce();
    Future<(CreatedSale, Map<String, dynamic>)> saleAndVoid() async {
      final sale = await LocalSaleService(db, const UuidV7Generator()).createSale(SaleDraft(
        shopId: f.shopId,
        cashierId: f.ownerId,
        deviceId: f.deviceA,
        customerId: f.customerId,
        lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
        payments: const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 18000)],
      ));
      await upload();
      final voidId = await LocalSaleVoidService(db, const UuidV7Generator()).voidSale(
          shopId: f.shopId, saleId: sale.saleId, ownerId: f.ownerId, deviceId: f.deviceA, reason: 'wrong');
      final op = await (db.select(db.syncOperations)..where((t) => t.entityId.equals(voidId))).getSingle();
      await (db.update(db.syncOperations)..where((t) => t.id.equals(op.id)))
          .write(const SyncOperationsCompanion(status: Value(SyncStatus.synced)));
      return (sale, jsonDecode(op.payload) as Map<String, dynamic>);
    }

    // Before the upgrade: a device on the R1.2 build sent a v1 void.
    final (oldSale, oldV2) = await saleAndVoid();
    final v1 = Map<String, dynamic>.of(oldV2)
      ..['version'] = 1
      ..remove('movement_ids')
      ..remove('refund_ledger_id');
    expect(await _callVoid(f.ownerId, v1), contains('"inserted"'));
    final oldVoidId = (v1['void'] as Map)['id'] as String;
    Future<String> history() => psql('''
select md5(coalesce((select string_agg(t::text, '|' order by id) from sale_voids t where original_sale_id='${oldSale.saleId}'),'')
  || coalesce((select string_agg(t::text, '|' order by id) from inventory_movements t where reference_id='$oldVoidId'),'')
  || coalesce((select string_agg(t::text, '|' order by id) from customer_ledger_entries t where sale_id='${oldSale.saleId}'),'')
  || coalesce((select string_agg(t::text, '|' order by id) from audit_logs t where entity_id='$oldVoidId'),''));''');
    final before = await history();
    expect(await psql("select count(*) from inventory_movements where reference_id='$oldVoidId'"), '1');

    for (final file in migrationFiles().skip(_r12MigrationCount)) {
      await psql(file.readAsStringSync());
    }

    expect(await history(), before, reason: 'historical void rows are untouched');
    // Even an identical replay of the accepted v1 void is refused: its device
    // compensation ids differ from the server's, so it is not acknowledged as
    // synced; it stays for owner reconciliation (R1.5).
    expect(await _callVoid(f.ownerId, v1), startsWith('DPV01 '));
    expect(await history(), before);
    final (newSale, newV2) = await saleAndVoid();
    final newV1 = Map<String, dynamic>.of(newV2)
      ..['version'] = 1
      ..remove('movement_ids')
      ..remove('refund_ledger_id');
    expect(await _callVoid(f.ownerId, newV1), startsWith('DPV01 '));
    expect(await psql("select count(*) from sale_voids where original_sale_id='${newSale.saleId}'"), '0');
    expect(await _callVoid(f.ownerId, newV2), contains('"inserted"'));
    final newVoidId = (newV2['void'] as Map)['id'] as String;
    expect(await psql("select id from inventory_movements where reference_id='$newVoidId'"),
        (newV2['movement_ids'] as Map).values.single);
    expect(await psql("select id from customer_ledger_entries where type='refund' and sale_id='${newSale.saleId}'"),
        newV2['refund_ledger_id']);
  }, skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker');
}
