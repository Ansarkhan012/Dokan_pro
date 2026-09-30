// Expected-red reproduction of F-1 (checkout coupled to network sync) and O-6
// (lease error escaping SyncWorker.runOnce). Pure local: no Docker, no network.
// Each test asserts the CORRECT contract and fails on current code.
//
// Data layer: `_ProductionShapedCommitter.complete` mirrors
// lib/features/pos/pos_runtime_native.dart `_NativeSaleCommitter.complete`
// line for line (local commit, awaited SyncWorker.runOnce, return); that class
// is private, so only the upload gateway is injected.
// UI layer: a Drift-free committer reproduces what `complete()` does after a
// commit (throw or never return), so the widget tests own no database handle,
// no background timer and no pending future after teardown.
@Tags(['recovery-red'])
library;

import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter/material.dart';
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

final class _ProductionShapedCommitter implements PosSaleCommitter {
  _ProductionShapedCommitter(this.db, this.gateway);
  final AppDatabase db;
  final SaleUploadGateway gateway;
  bool _lastSyncSucceeded = false;

  @override
  bool get lastSyncSucceeded => _lastSyncSucceeded;

  @override
  Future<CreatedSale> complete(PosCart cart, PosPaymentPlan payment) async {
    final created = await LocalSaleService(db, const UuidV7Generator()).createSale(
      SaleDraft(
        shopId: _shop,
        cashierId: _owner,
        deviceId: _device,
        customerId: payment.customerId,
        lines: cart.toSaleLines(),
        payments: payment.payments
            .map((row) => SalePaymentDraft(method: row.method, amountMinor: row.amountMinor))
            .toList(),
      ),
    );
    _lastSyncSucceeded = await syncPending();
    return created;
  }

  Future<bool> syncPending() async {
    final queue = SyncQueueRepository(db, shopId: _shop);
    await SyncWorker(queue: queue, gateway: gateway, workerId: 'device-$_device').runOnce();
    return (await queue.pending()).isEmpty;
  }

  @override
  Future<bool> triggerSync() => syncPending();
  @override
  Future<PosCatalogSnapshot> reloadCatalog() => throw UnimplementedError();
  @override
  Stream<bool> watchHasPendingSync() => const Stream.empty();
  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {}
  @override
  Future<List<CustomerAccount>> searchCustomers(String query) async => [];
  @override
  Future<List<CustomerLedgerLine>> statement(String customerId) async => [];
}

/// UI-layer stand-in with no database: behaves like the production committer
/// after its local commit when the awaited sync throws or never returns.
final class _AfterCommitCommitter implements PosSaleCommitter {
  _AfterCommitCommitter({required this.hang});
  final bool hang;
  final pending = Completer<CreatedSale>();
  int calls = 0;

  @override
  Future<CreatedSale> complete(PosCart cart, PosPaymentPlan payment) {
    calls++;
    if (hang) return pending.future;
    return Future.error(StateError('Worker does not own sync lease'));
  }

  /// Releases the never-completing future so nothing survives teardown.
  void release() {
    if (!pending.isCompleted) pending.completeError(StateError('test teardown'));
  }

  @override
  bool get lastSyncSucceeded => false;
  @override
  Future<bool> triggerSync() async => false;
  @override
  Future<PosCatalogSnapshot> reloadCatalog() async => _catalog;
  @override
  Stream<bool> watchHasPendingSync() => const Stream.empty();
  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {}
  @override
  Future<List<CustomerAccount>> searchCustomers(String query) async => [];
  @override
  Future<List<CustomerLedgerLine>> statement(String customerId) async => [];
}

const _catalog = PosCatalogSnapshot(
  products: [
    PosProduct(
      id: _product,
      name: 'Coke',
      salePriceMinor: 18000,
      stockQuantity: 10000,
      stockTrackingEnabled: true,
    ),
  ],
  categories: [],
  customers: [],
);

/// Never queried by these tests (the Bills tab is not opened); closed in
/// tearDownAll outside the fake-async zone.
late AppDatabase _historyDb;

Future<void> _pumpPos(WidgetTester tester, PosSaleCommitter committer) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: PosWorkspace(
      shopName: 'Shop',
      cashierName: 'cashier',
      initialCatalog: _catalog,
      committer: committer,
      salesHistory: DriftSalesHistoryRepository(_historyDb, shopId: _shop),
      offline: false,
      initialHasPendingSync: false,
      onLogout: () async {},
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _ringUpAndPay(WidgetTester tester) async {
  await tester.tap(find.text('Add').first);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('pay-button')));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Complete Sale'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Disposes the widget tree (cancels PosWorkspace's periodic retry timer) and
/// lets snack bars and animations finish so no timer outlives the test.
Future<void> _disposePos(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  setUpAll(() => _historyDb = AppDatabase(NativeDatabase.memory()));
  tearDownAll(() => _historyDb.close());

  test(
    'F-1 data layer: post-commit sync failure escapes, cart is not cleared, retry creates a second sale',
    () async {
      final db = await _seed();
      addTearDown(db.close);
      final committer = _ProductionShapedCommitter(db, _LeaseLostGateway(db));
      final cart = PosCart()..add(_catalog.products.single);
      const plan = PosPaymentPlan(
        payments: [PosPayment(method: PaymentMethod.cash, amountMinor: 18000)],
        cashReceivedMinor: 18000,
      );
      Future<Object?> attempt() async {
        try {
          await const PosCheckoutController().complete(
            cart: cart, payment: plan, commit: () => committer.complete(cart, plan),
          );
          return null;
        } catch (e) {
          return e;
        }
      }

      final firstError = await attempt();
      final salesAfterFirst = (await db.select(db.sales).get()).length;
      final cartClearedAfterFirst = cart.isEmpty;
      final retryError = await attempt();
      final sales = await db.select(db.sales).get();
      // ignore: avoid_print
      print('F1_DATA_EVIDENCE first error=$firstError | sales after first=$salesAfterFirst | '
          'cart cleared=$cartClearedAfterFirst | retry error=$retryError | '
          'sales after retry=${sales.length}');
      expect(salesAfterFirst, 1);
      expect(firstError, isNull, reason: 'a committed sale must be reported as completed');
      expect(sales.length, 1, reason: 'one real checkout must be one financial sale');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

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

  testWidgets(
    'F-1 UI layer (throw): committed sale must not be reported as "Nothing was charged"',
    (tester) async {
      final committer = _AfterCommitCommitter(hang: false);
      await _pumpPos(tester, committer);
      await _ringUpAndPay(tester);
      final nothingCharged = find.textContaining('Nothing was charged').evaluate().isNotEmpty;
      final cartStillPayable = find.text('Pay Rs 180.00').evaluate().isNotEmpty;
      // ignore: avoid_print
      print('F1_UI_THROW_EVIDENCE complete() calls=${committer.calls}, '
          '"Nothing was charged" shown=$nothingCharged, Pay button still armed=$cartStillPayable');
      await _disposePos(tester);
      expect(nothingCharged, isFalse);
      expect(cartStillPayable, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'F-1 UI layer (hang): committed sale must show a receipt, not an endless spinner',
    (tester) async {
      final committer = _AfterCommitCommitter(hang: true);
      await _pumpPos(tester, committer);
      await _ringUpAndPay(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      final spinner = find.text('Completing…').evaluate().isNotEmpty;
      final receipt = find.text('View receipt').evaluate().isNotEmpty;
      // ignore: avoid_print
      print('F1_UI_HANG_EVIDENCE after 30s simulated: "Completing…" shown=$spinner, receipt shown=$receipt');
      committer.release();
      await _disposePos(tester);
      expect(spinner, isFalse);
      expect(receipt, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
