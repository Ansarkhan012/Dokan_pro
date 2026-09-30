// Simulated POS device for R1 integration tests: an independent, file-backed
// Drift database (so a process restart can be simulated by close + reopen),
// its own clock, and a fault-injecting wrapper around the application's real
// SupabaseSaleUploadGateway. Reference data arrives through the application's
// real pull path (ReferencePullService + SupabaseReferencePullGateway).

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/pull/supabase_reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/supabase_sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';

import 'http_stack.dart';

/// Network behaviour of one simulated device.
enum SimNetwork {
  online,

  /// Fails before sending: nothing reaches the server.
  offline,

  /// Sends the request, the server commits, then the response is lost.
  dropResponse,
}

/// Same pull set and order as lib/features/pos/pos_runtime_native.dart.
const posPullEntities = [
  PullEntity.shops,
  PullEntity.devices,
  PullEntity.cashiers,
  PullEntity.categories,
  PullEntity.masterProducts,
  PullEntity.shopProducts,
  PullEntity.customers,
  PullEntity.customerLedgerEntries,
  PullEntity.inventoryMovements,
  PullEntity.sales,
  PullEntity.saleItems,
  PullEntity.salePayments,
  PullEntity.saleReturns,
  PullEntity.saleReturnItems,
  PullEntity.saleVoids,
];

final class _FaultInjectingGateway implements SaleUploadGateway {
  _FaultInjectingGateway(this.device, this.inner);
  final SimDevice device;
  final SaleUploadGateway inner;
  var uploads = 0;

  @override
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) async {
    switch (device.network) {
      case SimNetwork.offline:
        throw const SocketException('simulated offline device');
      case SimNetwork.dropResponse:
        await inner.uploadSaleAggregate(payload, cashierSessionToken: cashierSessionToken);
        uploads++;
        throw TimeoutException('simulated lost response after server commit');
      case SimNetwork.online:
        await inner.uploadSaleAggregate(payload, cashierSessionToken: cashierSessionToken);
        uploads++;
    }
  }
}

final class SimDevice {
  SimDevice._(this.label, this.shop, this.deviceId, this._dir, this.db);

  final String label;
  final ServerShop shop;
  final String deviceId;
  final Directory _dir;
  AppDatabase db;
  SimNetwork network = SimNetwork.online;

  /// Offset applied to real time (e.g. a fast or slow device clock).
  Duration clockSkew = Duration.zero;
  DateTime now() => DateTime.now().toUtc().add(clockSkew);

  late final _gateway = _FaultInjectingGateway(
    this,
    SupabaseSaleUploadGateway(shop.owner.client),
  );
  int get serverUploads => _gateway.uploads;

  File get _file => File('${_dir.path}${Platform.pathSeparator}device.sqlite');

  static Future<SimDevice> open(String label, ServerShop shop, String deviceId) async {
    final dir = Directory.systemTemp.createTempSync('r1_device_${label}_');
    final db = AppDatabase(
      NativeDatabase(File('${dir.path}${Platform.pathSeparator}device.sqlite')),
    );
    final device = SimDevice._(label, shop, deviceId, dir, db);
    await device.pull();
    // The app has no shop_users pull; the owner acts as the sales actor in
    // these tests (the production POS uses a pulled cashier instead).
    await db.into(db.shopUsers).insertOnConflictUpdate(ShopUsersCompanion.insert(
      id: 'owner-${shop.owner.userId}',
      shopId: shop.shopId,
      userId: shop.owner.userId,
      role: ShopRole.owner,
      createdAt: DateTime.now().toUtc(),
    ));
    return device;
  }

  Future<void> pull([List<PullEntity> entities = posPullEntities]) async {
    final service = ReferencePullService(
      db,
      SupabaseReferencePullGateway(shop.owner.client),
      shopId: shop.shopId,
    );
    for (final entity in entities) {
      await service.pull(entity);
    }
  }

  Future<CreatedSale> sell({
    String? productId,
    int quantity = 1000,
    List<SalePaymentDraft>? payments,
    String? customerId,
  }) {
    final product = productId ?? shop.productId;
    return LocalSaleService(db, const UuidV7Generator(), clock: now).createSale(
      SaleDraft(
        shopId: shop.shopId,
        cashierId: shop.owner.userId,
        deviceId: deviceId,
        customerId: customerId,
        lines: [SaleLineDraft(productId: product, quantity: quantity)],
        payments: payments ??
            [
              SalePaymentDraft(
                method: PaymentMethod.cash,
                amountMinor: (ServerShop.salePrice * quantity + 500) ~/ 1000,
              ),
            ],
      ),
    );
  }

  Future<SyncWorkerResult> sync() => SyncWorker(
        queue: SyncQueueRepository(db, shopId: shop.shopId),
        gateway: _gateway,
        workerId: 'sim-$label',
        clock: now,
      ).runOnce();

  /// Simulates process death and restart: the file-backed database survives.
  Future<void> restart() async {
    await db.close();
    db = AppDatabase(NativeDatabase(_file));
  }

  Future<int> stock(String productId) async => (await db
          .customSelect(
            'select coalesce(sum(quantity),0) q from inventory_movements where product_id=?',
            variables: [Variable(productId)],
          )
          .getSingle())
      .read<int>('q');

  Future<bool> hasSale(String saleId) async =>
      (await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingleOrNull()) != null;

  Future<List<SyncOperation>> queue() => db.select(db.syncOperations).get();

  Future<void> dispose() async {
    await db.close();
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
  }
}
