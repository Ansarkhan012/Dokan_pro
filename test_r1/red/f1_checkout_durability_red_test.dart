// Expected-red reproduction of O-6 (lease error escaping SyncWorker.runOnce).
// Pure local: no Docker, no network. Asserts the CORRECT contract and fails
// on current code.
//
// The F-1 tests that shared this file (data layer, UI throw, UI hang) were
// fixed by R1.1 and moved, unchanged in name and assertions, to
// test_r1/green/f1_checkout_durability_test.dart. O-6 itself stays red until
// R1.6: R1.1's background SyncWorkerRunner only contains the escaping error.
@Tags(['recovery-red'])
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

const _shop = 'shop', _owner = 'owner', _device = 'device', _product = 'coke';

Future<AppDatabase> _seed() async {
  final db = AppDatabase(NativeDatabase.memory());
  final t = DateTime.utc(2026, 9, 1);
  await db.into(db.shops).insert(ShopsCompanion.insert(
    id: _shop, name: 'Shop', phone: '', address: '',
    subscriptionPlan: SubscriptionPlan.trial,
    subscriptionStatus: SubscriptionStatus.trial,
    createdAt: t, updatedAt: t,
  ));
  await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
    id: 'm', shopId: _shop, userId: _owner, role: ShopRole.owner, createdAt: t,
  ));
  await db.into(db.devices).insert(DevicesCompanion.insert(
    id: _device, shopId: _shop, deviceName: 'd',
    deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: t,
  ));
  await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
    id: _product, shopId: _shop, customName: const Value('Coke'),
    purchasePrice: 15000, salePrice: 18000, createdAt: t, updatedAt: t,
  ));
  return db;
}

/// Server accepts the upload, but meanwhile another worker took the lease
/// (the 2-minute lease expired on a slow network). completeLease then throws,
/// the catch calls failLease, which throws again.
final class _LeaseLostGateway implements SaleUploadGateway {
  _LeaseLostGateway(this.db);
  final AppDatabase db;
  @override
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) => db.customStatement(
    "update sync_operations set lease_owner='other-worker' where status='syncing'",
  );
}

void main() {
  test(
    'O-6: SyncWorker.runOnce must not throw when its lease was lost after a successful upload',
    () async {
      final db = await _seed();
      addTearDown(db.close);
      await LocalSaleService(db, const UuidV7Generator()).createSale(
        const SaleDraft(
          shopId: _shop,
          cashierId: _owner,
          deviceId: _device,
          lines: [SaleLineDraft(productId: _product, quantity: 1000)],
          payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000)],
        ),
      );
      final worker = SyncWorker(
        queue: SyncQueueRepository(db, shopId: _shop),
        gateway: _LeaseLostGateway(db),
        workerId: 'device-$_device',
      );
      Object? escaped;
      try {
        await worker.runOnce();
      } catch (e) {
        escaped = e;
      }
      // ignore: avoid_print
      print('O6_EVIDENCE exception escaping runOnce: $escaped');
      expect(escaped, isNull, reason: 'runOnce must record the failure, not throw');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
