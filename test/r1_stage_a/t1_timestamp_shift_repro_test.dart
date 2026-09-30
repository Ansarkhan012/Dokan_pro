// R1 Stage A: NEW finding T-1 discovered while reproducing F-2.
// Asserts the CORRECT invariant, so it FAILS on the current code whenever the
// device time zone is not UTC (e.g. Asia/Karachi, UTC+05:00).
@Tags(['r1-repro'])
library;

import 'dart:convert';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpAll(() async {
    if (r1ServerEnabled) await createScratchServer();
  });
  tearDownAll(() async {
    if (r1ServerEnabled) await dropScratchServer();
  });

  test(
    'T-1: synced sale keeps its real instant on the server',
    () async {
      final f = ShopFixture();
      await f.seedServer();
      final db = await f.openDevice();
      addTearDown(db.close);
      final soldAt = DateTime.now().toUtc();
      final sale = await LocalSaleService(db, const UuidV7Generator(), clock: () => soldAt)
          .createSale(
        SaleDraft(
          shopId: f.shopId,
          cashierId: f.ownerId,
          deviceId: f.deviceA,
          lines: [SaleLineDraft(productId: f.productId, quantity: 1000)],
          payments: const [
            SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000),
          ],
        ),
      );
      final queued = await db.select(db.syncOperations).getSingle();
      final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
      final queuedCreatedAt = (payload['sale'] as Map)['createdAt'];
      final uploadedCreatedAt =
          (normalizeSalePayloadForCloud(payload)['sale'] as Map)['createdAt'];
      await SyncWorker(
        queue: SyncQueueRepository(db, shopId: f.shopId),
        gateway: PsqlUploadGateway(f.ownerId),
        workerId: 'device-A',
      ).runOnce();
      final serverCreatedAt = DateTime.parse(
        await psql(
          "select to_json(created_at)#>>'{}' from sales where id='${sale.saleId}'",
        ),
      ).toUtc();
      final serverMovementAt = DateTime.parse(
        await psql(
          "select to_json(min(created_at))#>>'{}' from inventory_movements where reference_id='${sale.saleId}'",
        ),
      ).toUtc();
      final skew = serverCreatedAt.difference(soldAt);
      // ignore: avoid_print
      print('''
T1_EVIDENCE
  device time zone        ${DateTime.now().timeZoneName} (offset ${DateTime.now().timeZoneOffset})
  real sale instant (UTC) ${soldAt.toIso8601String()}
  queued payload createdAt $queuedCreatedAt
  uploaded createdAt      $uploadedCreatedAt
  server sales.created_at ${serverCreatedAt.toIso8601String()}
  server movement created ${serverMovementAt.toIso8601String()}
  server - real           $skew
''');
      expect(skew.inSeconds.abs(), lessThanOrEqualTo(1));
    },
    skip: r1ServerEnabled ? false : 'needs --dart-define=R1_SERVER=true and local Docker',
  );
}
