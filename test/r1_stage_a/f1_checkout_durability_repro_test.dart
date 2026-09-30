// R1 Stage A reproduction of audit finding F-1 (checkout coupled to network
// sync). Pure local: no Docker, no network. Asserts the CORRECT contract, so
// the tests FAIL on the current code.
//
// `_ProductionShapedCommitter.complete` mirrors
// lib/features/pos/pos_runtime_native.dart `_NativeSaleCommitter.complete`
// line for line (local commit, then awaited SyncWorker.runOnce, then return);
// only the upload gateway is injected. That class is private, so it cannot be
// constructed directly from a test.
@Tags(['r1-repro'])
library;

import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
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

/// Upload succeeds on the server, but another worker has taken over the lease
/// meanwhile (lease expiry after 2 minutes on a slow network). With the
/// current code completeLease throws, the catch calls failLease, which throws
/// again, and the exception escapes SyncWorker.runOnce.
final class _LeaseLostGateway implements SaleUploadGateway {
  _LeaseLostGateway(this.db);
  final AppDatabase db;
  @override
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) async {
    await db.customStatement(
      "update sync_operations set lease_owner='other-worker' where status='syncing'",
    );
  }
}

/// Network request that never completes (no timeout on client.rpc).
final class _HangingGateway implements SaleUploadGateway {
  final never = Completer<void>();
  @override
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) => never.future;
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
    final created = await LocalSaleService(db, const UuidV7Generator())
        .createSale(
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
    await SyncWorker(queue: queue, gateway: gateway, workerId: 'device-$_device')
        .runOnce();
    return (await queue.pending()).isEmpty;
  }

  @override
  Future<bool> triggerSync() => syncPending();
  @override
  Future<PosCatalogSnapshot> reloadCatalog() => DriftPosCatalog(db, shopId: _shop).load();
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


/// UI-layer stand-in: the sale is already committed (by the data-layer path
/// above); complete() then fails or hangs exactly like the production
/// committer does when its awaited sync throws or never returns.
final class _AfterCommitCommitter extends _ProductionShapedCommitter {
  _AfterCommitCommitter(super.db, super.gateway, {required this.hang});
  final bool hang;
  final never = Completer<CreatedSale>();
  int calls = 0;
  @override
  Future<CreatedSale> complete(PosCart cart, PosPaymentPlan payment) {
    calls++;
    if (hang) return never.future;
    return Future.error(StateError('Worker does not own sync lease'));
  }
}

Future<void> _pumpPos(WidgetTester tester, PosSaleCommitter committer) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() => tester.runAsync(db.close));
  await tester.pumpWidget(MaterialApp(
    home: PosWorkspace(
      shopName: 'Shop',
      cashierName: 'cashier',
      initialCatalog: const PosCatalogSnapshot(
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
      ),
      committer: committer,
      salesHistory: DriftSalesHistoryRepository(db, shopId: _shop),
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

void main() {
  test(
    'F-1 data layer: post-commit sync failure escapes, cart is not cleared, retry creates a second sale',
    () async {
      final db = await _seed();
      addTearDown(db.close);
      final committer = _ProductionShapedCommitter(db, _LeaseLostGateway(db));
      final cart = PosCart()
        ..add(const PosProduct(
          id: _product, name: 'Coke', salePriceMinor: 18000,
          stockQuantity: 10000, stockTrackingEnabled: true,
        ));
      const plan = PosPaymentPlan(
        payments: [PosPayment(method: PaymentMethod.cash, amountMinor: 18000)],
        cashReceivedMinor: 18000,
      );
      Object? firstError;
      try {
        await const PosCheckoutController().complete(
          cart: cart, payment: plan, commit: () => committer.complete(cart, plan),
        );
      } catch (e) {
        firstError = e;
      }
      final salesAfterFirst = (await db.select(db.sales).get()).length;
      final cartClearedAfterFirst = cart.isEmpty;
      Object? retryError;
      try {
        await const PosCheckoutController().complete(
          cart: cart, payment: plan, commit: () => committer.complete(cart, plan),
        );
      } catch (e) {
        retryError = e;
      }
      final sales = await db.select(db.sales).get();
      final queue = await db.select(db.syncOperations).get();
      // ignore: avoid_print
      print('F1_DATA_EVIDENCE first error=$firstError | sales after first=$salesAfterFirst | '
          'cart cleared=$cartClearedAfterFirst | retry error=$retryError | '
          'sales after retry=${sales.length} ids=${sales.map((s) => s.id).toList()} | '
          'queue=${queue.map((q) => '${q.status.name}/${q.leaseOwner}').toList()}');
      expect(salesAfterFirst, 1);
      expect(firstError, isNull, reason: 'a committed sale must be reported as completed');
      expect(sales.length, 1, reason: 'one real checkout must be one financial sale');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'F-1 UI layer (throw): committed sale must not be reported as "Nothing was charged"',
    (tester) async {
      final committer = _AfterCommitCommitter(
        AppDatabase(NativeDatabase.memory()), _HangingGateway(), hang: false,
      );
      await _pumpPos(tester, committer);
      await _ringUpAndPay(tester);
      final nothingCharged = find.textContaining('Nothing was charged').evaluate().isNotEmpty;
      final cartStillPayable = find.text('Pay Rs 180.00').evaluate().isNotEmpty;
      // ignore: avoid_print
      print('F1_UI_THROW_EVIDENCE complete() calls=${committer.calls}, '
          '"Nothing was charged" shown=$nothingCharged, Pay button still armed=$cartStillPayable');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(nothingCharged, isFalse);
      expect(cartStillPayable, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'F-1 UI layer (hang): committed sale must show a receipt, not an endless spinner',
    (tester) async {
      final committer = _AfterCommitCommitter(
        AppDatabase(NativeDatabase.memory()), _HangingGateway(), hang: true,
      );
      await _pumpPos(tester, committer);
      await _ringUpAndPay(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      final spinner = find.text('Completing…').evaluate().isNotEmpty;
      final receipt = find.text('View receipt').evaluate().isNotEmpty;
      // ignore: avoid_print
      print('F1_UI_HANG_EVIDENCE after 30s simulated: "Completing…" shown=$spinner, receipt shown=$receipt');
      expect(spinner, isFalse);
      expect(receipt, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
