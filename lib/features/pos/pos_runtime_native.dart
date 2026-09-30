import 'dart:async';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/cashier_session_manager.dart';
import '../../auth/cashier_session_store.dart';
import '../../auth/supabase_cashier_auth_gateway.dart';
import '../../core/domain/enums.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/pull/pull_models.dart';
import '../../sync/pull/reference_pull_service.dart';
import '../../sync/pull/supabase_reference_pull_gateway.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_worker_runner.dart';
import '../../subscription/entitlement_policy.dart';
import '../../subscription/subscription_runtime.dart';
import '../../subscription/entitlement_store.dart';
import '../../subscription/entitlement_verifier.dart';
import '../../subscription/supabase_entitlement_gateway.dart';
import '../sales/sales_history.dart';
import 'drift_pos_catalog.dart';
import 'drift_pos_sale_committer.dart';
import 'pos_catalog.dart';
import 'pos_workspace.dart';

class PosRuntime extends StatefulWidget {
  const PosRuntime({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
    required this.cashierId,
    required this.cashierName,
    required this.deviceId,
    required this.onExit,
  });

  final SupabaseClient client;
  final String shopId;
  final String shopName;
  final String cashierId;
  final String cashierName;
  final String deviceId;
  final VoidCallback onExit;

  @override
  State<PosRuntime> createState() => _PosRuntimeState();
}

class _PosRuntimeState extends State<PosRuntime> {
  AppDatabase? db;
  late Future<_RuntimeState> startup = _start();

  Future<_RuntimeState> _start() async {
    final database = await AppDatabase.open();
    db = database;
    final catalog = DriftPosCatalog(database, shopId: widget.shopId);
    final cached = await catalog.load();
    final hasCachedContext = await _hasCachedContext(database);
    final useCachedStartup = hasCachedContext && cached.products.isNotEmpty;
    final sync = _syncRunner(database);
    var offline = false;
    if (useCachedStartup) {
      unawaited(_refreshAndSync(database, sync));
    } else {
      offline = !await _pullReferences(database);
    }
    final snapshot = useCachedStartup ? cached : await catalog.load();
    final policy = productionEntitlementPolicy();
    var entitlement = await policy.evaluate(
      shopId: widget.shopId,
      deviceId: widget.deviceId,
      localNow: DateTime.now(),
    );
    final authorizer = EntitlementMutationAuthorizer(policy);
    if (entitlement.permitsMutation) {
      unawaited(_refreshEntitlement());
    } else {
      // First provisioning needs one bounded online issuance attempt. A cached
      // valid entitlement never waits on Supabase during startup.
      final refreshed = await _refreshEntitlement().timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
      if (refreshed) {
        entitlement = await policy.evaluate(
          shopId: widget.shopId,
          deviceId: widget.deviceId,
          localNow: DateTime.now(),
        );
      }
    }
    final committer = DriftPosSaleCommitter(
      database,
      shopId: widget.shopId,
      cashierId: widget.cashierId,
      deviceId: widget.deviceId,
      sync: sync,
      authorizer: authorizer,
    );
    if (!offline && !useCachedStartup) await sync.run();
    final shopOperations = await (database.select(
      database.syncOperations,
    )..where((row) => row.shopId.equals(widget.shopId))).get();
    return _RuntimeState(
      catalog: snapshot,
      committer: committer,
      offline: offline,
      hasPendingSync: shopOperations.any(
        (operation) => operation.status != SyncStatus.synced,
      ),
      entitlement: entitlement,
      lastSavedSale: await _lastSavedSale(database),
    );
  }

  /// One background upload runner per POS runtime; checkout only wakes it.
  SyncWorkerRunner _syncRunner(AppDatabase database) => SyncWorkerRunner(
    queue: SyncQueueRepository(database, shopId: widget.shopId),
    gateway: SupabaseSaleUploadGateway(widget.client),
    workerId: 'device-${widget.deviceId}',
    cashierToken: () async => (await SecureCashierSessionStore().read())?.token,
  );

  /// The newest sale committed on this device in the last 30 minutes, so a
  /// cashier whose app closed after checkout can reprint instead of re-ringing.
  Future<SaleHistoryRow?> _lastSavedSale(AppDatabase database) async {
    try {
      return await DriftSalesHistoryRepository(
        database,
        shopId: widget.shopId,
      ).lastSaleOnDevice(
        widget.deviceId,
        since: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
      );
    } catch (_) {
      return null; // A recovery hint must never block opening the POS.
    }
  }

  Future<bool> _refreshEntitlement() async {
    try {
      final store = SecureEntitlementStore();
      final verifier = EntitlementVerifier(rsaPublicKeyFromEnvironment());
      await SupabaseEntitlementGateway(widget.client, verifier, store).refresh(
        shopId: widget.shopId,
        deviceId: widget.deviceId,
        localNow: DateTime.now(),
      );
      return true;
    } catch (_) {
      // Cached entitlement remains authoritative during temporary outages.
      return false;
    }
  }

  Future<bool> _pullReferences(AppDatabase database) async {
    var succeeded = true;
    final pull = ReferencePullService(
      database,
      SupabaseReferencePullGateway(widget.client),
      shopId: widget.shopId,
    );
    for (final entity in const [
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
    ]) {
      try {
        await pull.pull(entity).timeout(const Duration(seconds: 8));
      } catch (_) {
        succeeded = false;
      }
    }
    return succeeded;
  }

  Future<bool> _hasCachedContext(AppDatabase database) async {
    final shop = await (database.select(
      database.shops,
    )..where((row) => row.id.equals(widget.shopId))).getSingleOrNull();
    final cashier =
        await (database.select(database.cashiers)..where(
              (row) =>
                  row.id.equals(widget.cashierId) &
                  row.shopId.equals(widget.shopId) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    final device =
        await (database.select(database.devices)..where(
              (row) =>
                  row.id.equals(widget.deviceId) &
                  row.shopId.equals(widget.shopId) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    return shop != null && cashier != null && device != null;
  }

  Future<void> _refreshAndSync(
    AppDatabase database,
    SyncWorkerRunner sync,
  ) async {
    await _pullReferences(database);
    await sync.run();
  }

  Future<void> _logout() async {
    try {
      await CashierSessionManager(
        SupabaseCashierAuthGateway(widget.client),
        SecureCashierSessionStore(),
      ).logout();
    } catch (_) {
      await SecureCashierSessionStore().clear();
    }
    if (mounted) widget.onExit();
  }

  @override
  void dispose() {
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_RuntimeState>(
    future: startup,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.shopName)),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The local POS could not be opened. Check this device’s local storage and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() => startup = _start()),
                    child: const Text('Retry'),
                  ),
                  TextButton(onPressed: _logout, child: const Text('Log out')),
                ],
              ),
            ),
          ),
        );
      }
      final state = snapshot.data!;
      return PosWorkspace(
        shopName: widget.shopName,
        cashierName: widget.cashierName,
        initialCatalog: state.catalog,
        committer: state.committer,
        salesHistory: DriftSalesHistoryRepository(db!, shopId: widget.shopId),
        offline: state.offline,
        initialHasPendingSync: state.hasPendingSync,
        entitlement: state.entitlement,
        lastSavedSale: state.lastSavedSale,
        onLogout: _logout,
      );
    },
  );
}

final class _RuntimeState {
  const _RuntimeState({
    required this.catalog,
    required this.committer,
    required this.offline,
    required this.hasPendingSync,
    required this.entitlement,
    required this.lastSavedSale,
  });
  final PosCatalogSnapshot catalog;
  final PosSaleCommitter committer;
  final bool offline;
  final bool hasPendingSync;
  final EntitlementEvaluation entitlement;
  final SaleHistoryRow? lastSavedSale;
}
