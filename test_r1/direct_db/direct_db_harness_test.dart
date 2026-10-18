// Green smoke test for the fast direct-database layer: a per-file scratch
// database with all migrations from zero, two device databases, sale upload
// and pull through the real Drift services. Requires Docker.
@Tags(['r1-direct-db'])
library;

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/direct_db_server.dart';

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer('smoke');
  });
  tearDownAll(() async {
    if (!r1ServerEnabled) return;
    await dropScratchServer();
    expect(
      await psql("select count(*) from pg_database where datname = '$scratchDb'", db: 'postgres'),
      '0',
      reason: 'scratch database must be dropped',
    );
  });

  test(
    'scratch server built from all migrations serves two devices',
    () async {
      expect(await psql("select count(*) from pg_tables where schemaname = 'public'"), isNot('0'));
      final f = ShopFixture();
      await f.seedServer();
      final a = await f.openDevice();
      final b = await f.openDevice();
      addTearDown(a.close);
      addTearDown(b.close);
      final sale = await LocalSaleService(a, const UuidV7Generator()).createSale(
        SaleDraft(
          shopId: f.shopId,
          cashierId: f.ownerId,
          deviceId: f.deviceA,
          lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
          payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000)],
        ),
      );
      final result = await SyncWorker(
        queue: SyncQueueRepository(a, shopId: f.shopId),
        gateway: PsqlUploadGateway(f.ownerId),
        workerId: 'A',
      ).runOnce();
      expect(result.synced, 1);
      final pull = ReferencePullService(b, PsqlPullGateway(f.ownerId), shopId: f.shopId);
      await pull.pull(PullEntity.sales);
      await pull.pull(PullEntity.inventoryMovements);
      expect(await (b.select(b.sales)..where((t) => t.id.equals(sale.saleId))).getSingleOrNull(), isNotNull);
      expect(await localStock(b, f.productId), ShopFixture.openingStock - 1000);
    },
    skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
  );
}
