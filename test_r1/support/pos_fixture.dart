// Local POS fixture for the R1.1 checkout suite: a seeded Drift database, the
// real production committer (DriftPosSaleCommitter) and its real background
// SyncWorkerRunner, with a scriptable upload gateway. No Docker, no network.
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/pos/drift_pos_sale_committer.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_worker_runner.dart';

const shopId = 'shop', ownerId = 'owner', deviceId = 'device';
const cokeId = 'coke', freeId = 'free-bag', customerId = 'ahmed';
const cokePrice = 18000; // Rs 180.00
const openingStock = 10000; // 10 units

const coke = PosProduct(
  id: cokeId,
  name: 'Coke',
  salePriceMinor: cokePrice,
  stockQuantity: openingStock,
  stockTrackingEnabled: true,
);
const freeBag = PosProduct(
  id: freeId,
  name: 'Free bag',
  salePriceMinor: 0,
  stockQuantity: openingStock,
  stockTrackingEnabled: true,
);

const cashPlan = PosPaymentPlan(
  payments: [PosPayment(method: PaymentMethod.cash, amountMinor: cokePrice)],
  cashReceivedMinor: cokePrice,
);
const udhaarPlan = PosPaymentPlan(
  payments: [PosPayment(method: PaymentMethod.credit, amountMinor: cokePrice)],
  customerId: customerId,
);

PosCart cartOf(List<PosProduct> products) {
  final cart = PosCart();
  for (final product in products) {
    cart.add(product);
  }
  return cart;
}

/// How the scripted server behaves for the background sync.
enum GatewayMode {
  /// Accepts the upload.
  accept,

  /// Throws like a failed RPC.
  fail,

  /// Throws synchronously, before any future exists.
  throwSync,

  /// Accepts, but another worker took the lease meanwhile: completeLease and
  /// failLease then throw out of SyncWorker.runOnce (the F-1 / O-6 shape).
  leaseLost,

  /// Never answers.
  hang,
}

final class ScriptedGateway implements SaleUploadGateway {
  ScriptedGateway(this.db, this.mode);
  final AppDatabase? db;
  GatewayMode mode;
  int calls = 0;
  final _never = Completer<void>();

  @override
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) {
    calls++;
    return switch (mode) {
      GatewayMode.accept => Future.value(),
      GatewayMode.fail => Future.error(StateError('simulated RPC failure')),
      GatewayMode.throwSync => throw StateError('simulated synchronous failure'),
      GatewayMode.leaseLost => db!.customStatement(
        "update sync_operations set lease_owner='other-worker' where status='syncing'",
      ),
      GatewayMode.hang => _never.future,
    };
  }
}

Future<void> seed(AppDatabase db) async {
  final t = DateTime.utc(2026, 9, 1);
  await db.into(db.shops).insert(ShopsCompanion.insert(
    id: shopId, name: 'Shop', phone: '', address: '',
    subscriptionPlan: SubscriptionPlan.trial,
    subscriptionStatus: SubscriptionStatus.trial,
    createdAt: t, updatedAt: t,
  ));
  await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
    id: 'm', shopId: shopId, userId: ownerId, role: ShopRole.owner, createdAt: t,
  ));
  await db.into(db.devices).insert(DevicesCompanion.insert(
    id: deviceId, shopId: shopId, deviceName: 'd',
    deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: t,
  ));
  for (final (id, name, price) in [(cokeId, 'Coke', cokePrice), (freeId, 'Free bag', 0)]) {
    await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
      id: id, shopId: shopId, customName: Value(name),
      purchasePrice: price == 0 ? 0 : 15000, salePrice: price, createdAt: t, updatedAt: t,
    ));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
      id: 'opening-$id', shopId: shopId, productId: id,
      type: InventoryMovementType.openingStock, quantity: openingStock,
      createdBy: ownerId, createdAt: t,
    ));
  }
  await db.into(db.customers).insert(CustomersCompanion.insert(
    id: customerId, shopId: shopId, name: 'Ahmed', createdAt: t, updatedAt: t,
  ));
}

/// One POS runtime: database + production committer + background runner.
final class PosHarness {
  PosHarness._(this.db, this.gateway, this.runner, this.committer, this._file);

  final AppDatabase db;
  final ScriptedGateway gateway;
  final SyncWorkerRunner runner;
  final DriftPosSaleCommitter committer;
  final File? _file;

  static Future<PosHarness> open({
    GatewayMode mode = GatewayMode.accept,
    Duration rpcTimeout = SyncWorkerRunner.defaultRpcTimeout,
    File? file,
    bool seeded = false,
  }) async {
    final db = AppDatabase(file == null ? NativeDatabase.memory() : NativeDatabase(file));
    if (!seeded) await seed(db);
    return attach(db, mode: mode, rpcTimeout: rpcTimeout, file: file);
  }

  static PosHarness attach(
    AppDatabase db, {
    GatewayMode mode = GatewayMode.accept,
    Duration rpcTimeout = SyncWorkerRunner.defaultRpcTimeout,
    File? file,
  }) {
    final gateway = ScriptedGateway(db, mode);
    final runner = SyncWorkerRunner(
      queue: SyncQueueRepository(db, shopId: shopId),
      gateway: gateway,
      workerId: 'device-$deviceId',
      rpcTimeout: rpcTimeout,
    );
    final committer = DriftPosSaleCommitter(
      db,
      shopId: shopId,
      cashierId: ownerId,
      deviceId: deviceId,
      sync: runner,
      authorizer: const AllowFinancialMutations(),
    );
    return PosHarness._(db, gateway, runner, committer, file);
  }

  File? get file => _file;

  Future<int> count(String table) async => (await db
          .customSelect('select count(*) c from $table')
          .getSingle())
      .read<int>('c');

  /// Row counts of every table one checkout writes.
  Future<Map<String, int>> footprint() async => {
        for (final table in const [
          'sales',
          'sale_items',
          'sale_payments',
          'inventory_movements',
          'customer_ledger_entries',
          'audit_logs',
          'sync_operations',
        ])
          table: await count(table),
      };

  /// Full content of every table one checkout writes, for no-mutation proofs.
  Future<String> snapshot() async {
    final out = StringBuffer();
    for (final table in const [
      'sales',
      'sale_items',
      'sale_payments',
      'inventory_movements',
      'customer_ledger_entries',
      'audit_logs',
      'sync_operations',
    ]) {
      final rows = await db.customSelect('select * from $table order by id').get();
      out.writeln('$table: ${rows.map((r) => r.data).toList()}');
    }
    return out.toString();
  }

  Future<int> stock(String productId) async => (await db
          .customSelect(
            'select coalesce(sum(quantity),0) q from inventory_movements where product_id=?',
            variables: [Variable(productId)],
          )
          .getSingle())
      .read<int>('q');

  Future<List<SyncOperation>> outbox() => db.select(db.syncOperations).get();

  Future<void> close() async {
    await runner.idle;
    await db.close();
  }
}
