import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../database/app_database.dart';
import '../../subscription/entitlement_policy.dart';
import '../../subscription/subscription_runtime.dart';
import '../../sync/sync_worker_runner.dart';
import '../customers/customer_models.dart';
import '../customers/drift_customer_repository.dart';
import '../customers/local_customer_payment_service.dart';
import '../sales/application/local_sale_service.dart';
import '../sales/domain/sale_draft.dart';
import 'drift_pos_catalog.dart';
import 'pos_catalog.dart';
import 'pos_state.dart';
import 'pos_workspace.dart';

/// The POS committer: every financial action is one local Drift transaction;
/// the network is only ever reached through the background [sync] runner.
final class DriftPosSaleCommitter implements PosSaleCommitter {
  DriftPosSaleCommitter(
    this.db, {
    required this.shopId,
    required this.cashierId,
    required this.deviceId,
    required this.sync,
    FinancialMutationAuthorizer? authorizer,
  }) : authorizer = authorizer ?? productionFinancialMutationAuthorizer();

  final AppDatabase db;
  final String shopId;
  final String cashierId;
  final String deviceId;
  final SyncWorkerRunner sync;
  final FinancialMutationAuthorizer authorizer;

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

  /// Completes when the checkout's single local transaction has committed
  /// (sale, items, payments, stock, Udhaar, audit and outbox together) and
  /// throws only if that transaction did not commit. Replaying [checkoutId]
  /// returns the committed sale, or throws [CheckoutConflict] for different
  /// content. Never waits for, or fails because of, the network.
  @override
  Future<CreatedSale> complete(
    String checkoutId,
    PosCart cart,
    PosPaymentPlan payment,
  ) async {
    final created =
        await LocalSaleService(
          db,
          const UuidV7Generator(),
          authorizer: authorizer,
        ).createSale(
          SaleDraft(
            saleId: checkoutId,
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
    // Point of no return: the sale is committed and stays committed.
    sync.wake();
    return created;
  }

  @override
  Future<bool> triggerSync() => sync.run();

  @override
  Future<PosCatalogSnapshot> reloadCatalog() =>
      DriftPosCatalog(db, shopId: shopId).load();

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
    sync.wake();
  }
}
