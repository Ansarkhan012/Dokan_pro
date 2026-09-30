import 'dart:async';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/cashier_session_manager.dart';
import '../../auth/cashier_session_store.dart';
import '../../auth/supabase_cashier_auth_gateway.dart';
import '../../core/ids/id_generator.dart';
import '../../core/domain/enums.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/pull/pull_models.dart';
import '../../sync/pull/reference_pull_service.dart';
import '../../sync/pull/supabase_reference_pull_gateway.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_worker.dart';
import '../../subscription/entitlement_policy.dart';
import '../../subscription/subscription_runtime.dart';
import '../../subscription/entitlement_store.dart';
import '../../subscription/entitlement_verifier.dart';
import '../../subscription/supabase_entitlement_gateway.dart';
import '../sales/application/local_sale_service.dart';
import '../sales/sales_history.dart';
import '../customers/customer_models.dart';
import '../customers/drift_customer_repository.dart';
import '../customers/local_customer_payment_service.dart';
import '../sales/domain/sale_draft.dart';
import 'drift_pos_catalog.dart';
import 'pos_catalog.dart';
import 'pos_state.dart';
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
    var offline = false;
    if (useCachedStartup) {
      unawaited(_refreshAndSync(database));
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
    final committer = _NativeSaleCommitter(
      database,
      catalog,
      client: widget.client,
      shopId: widget.shopId,
      cashierId: widget.cashierId,
      deviceId: widget.deviceId,
      authorizer: authorizer,
    );
    if (!offline && !useCachedStartup) await committer.syncPending();
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
    );
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

  Future<void> _refreshAndSync(AppDatabase database) async {
    await _pullReferences(database);
    await _NativeSaleCommitter(
      database,
      DriftPosCatalog(database, shopId: widget.shopId),
      client: widget.client,
      shopId: widget.shopId,
      cashierId: widget.cashierId,
      deviceId: widget.deviceId,
    ).syncPending();
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
  });
  final PosCatalogSnapshot catalog;
  final PosSaleCommitter committer;
  final bool offline;
  final bool hasPendingSync;
  final EntitlementEvaluation entitlement;
}

final class _NativeSaleCommitter implements PosSaleCommitter {
  _NativeSaleCommitter(
    this.db,
    this.catalog, {
    required this.client,
    required this.shopId,
    required this.cashierId,
    required this.deviceId,
    FinancialMutationAuthorizer? authorizer,
  }) : authorizer = authorizer ?? productionFinancialMutationAuthorizer();

  final AppDatabase db;
  final DriftPosCatalog catalog;
  final SupabaseClient client;
  final String shopId;
  final String cashierId;
  final String deviceId;
  final FinancialMutationAuthorizer authorizer;
  bool _lastSyncSucceeded = false;

  @override
  bool get lastSyncSucceeded => _lastSyncSucceeded;

  @override
  Stream<bool> watchHasPendingSync() =>
      (db.select(db.syncOperations)..where(
            (row) =>
                row.shopId.equals(shopId) &
                row.status.equals(SyncStatus.synced.name).not(),
          ))
          .watch()
          .map((operations) => operations.isNotEmpty)
          .distinct();

  @override
  Future<CreatedSale> complete(PosCart cart, PosPaymentPlan payment) async {
    final created =
        await LocalSaleService(
          db,
          const UuidV7Generator(),
          authorizer: authorizer,
        ).createSale(
          SaleDraft(
            shopId: shopId,
            cashierId: cashierId,
            deviceId: deviceId,
            customerId: payment.customerId,
            lines: cart.toSaleLines(),
            payments: payment.payments
                .map(
                  (row) => SalePaymentDraft(
                    method: row.method,
                    amountMinor: row.amountMinor,
                  ),
                )
                .toList(),
          ),
        );
    _lastSyncSucceeded = await syncPending();
    return created;
  }

  Future<bool> syncPending() async {
    final queue = SyncQueueRepository(db, shopId: shopId);
    await SyncWorker(
      queue: queue,
      gateway: SupabaseSaleUploadGateway(client),
      workerId: 'device-$deviceId',
      cashierToken: () async =>
          (await SecureCashierSessionStore().read())?.token,
    ).runOnce();
    return (await queue.pending()).isEmpty;
  }

  @override
  Future<bool> triggerSync() => syncPending();

  @override
  Future<PosCatalogSnapshot> reloadCatalog() => catalog.load();

  @override
  Future<List<CustomerAccount>> searchCustomers(String query) =>
      DriftCustomerRepository(db, shopId: shopId).search(query);

  @override
  Future<List<CustomerLedgerLine>> statement(String customerId) =>
      DriftCustomerRepository(db, shopId: shopId).statement(customerId);

  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {
    await LocalCustomerPaymentService(
      db,
      const UuidV7Generator(),
      authorizer: authorizer,
    ).receive(
      shopId: shopId,
      customerId: customerId,
      actorId: cashierId,
      deviceId: deviceId,
      amountMinor: amountMinor,
      method: method,
      reference: reference,
      note: note,
    );
    _lastSyncSucceeded = await syncPending();
  }
}
