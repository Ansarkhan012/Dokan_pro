// Project audit (2026-10-12) regressions. See PROJECT_AUDIT.md.
// A-1: a void or return of a sale made on this device is queued behind that
//      sale's upload, so the cloud never sees it before the sale.
// A-2: a sale with two or more returns refuses a void with the real reason.
// A-3: the POS cart follows refreshed prices; the workspace reloads the
//      catalog when a background pull finishes.
// A-4: Khata "Receive payment" cannot record a second payment while the
//      first is still in flight.
// A-5: an upload that never answers is cut and recorded, not awaited forever.
// A-6: money and quantity input cannot overflow or throw on long digit runs.
// B-2: a catalog cut at the POS limits says so, in English and Urdu.
import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/customer_khata_view.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/products/product_management_native.dart'
    as products;
import 'package:dukaan_pro/features/purchases/purchase_management_native.dart'
    as purchases;
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_failure.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = DateTime.utc(2026, 10, 12, 5);

Future<AppDatabase> _shop() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.shops).insert(ShopsCompanion.insert(
    id: 'shop', name: 'Shop', phone: '', address: '',
    subscriptionPlan: SubscriptionPlan.trial,
    subscriptionStatus: SubscriptionStatus.trial,
    createdAt: _t, updatedAt: _t,
  ));
  await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
    id: 'm', shopId: 'shop', userId: 'owner', role: ShopRole.owner,
    createdAt: _t,
  ));
  await db.into(db.devices).insert(DevicesCompanion.insert(
    id: 'device', shopId: 'shop', deviceName: 'd',
    deviceType: DeviceType.androidTablet, deviceIdentifier: 'd',
    createdAt: _t,
  ));
  await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
    id: 'surf', shopId: 'shop', customName: const Value('Surf'),
    purchasePrice: 30000, salePrice: 35000, createdAt: _t, updatedAt: _t,
  ));
  await db.into(db.inventoryMovements).insert(
    InventoryMovementsCompanion.insert(
      id: 'open-surf', shopId: 'shop', productId: 'surf',
      type: InventoryMovementType.openingStock, quantity: 10000,
      createdBy: 'owner', createdAt: _t,
    ),
  );
  return db;
}

Future<CreatedSale> _sell(AppDatabase db, {int pieces = 3}) =>
    LocalSaleService(db, const UuidV7Generator(), clock: () => _t).createSale(
      SaleDraft(
        shopId: 'shop', cashierId: 'owner', deviceId: 'device',
        lines: [SaleLineDraft(productId: 'surf', quantity: pieces * 1000)],
        payments: [
          SalePaymentDraft(method: PaymentMethod.cash, amountMinor: pieces * 35000),
        ],
      ),
    );

Future<String> _void(AppDatabase db, String saleId) =>
    LocalSaleVoidService(db, const UuidV7Generator(),
            clock: () => _t.add(const Duration(minutes: 1)))
        .voidSale(
      shopId: 'shop', saleId: saleId, ownerId: 'owner', deviceId: 'device',
      reason: 'wrong item',
    );

Future<CreatedSaleReturn> _return(AppDatabase db, String saleId) async {
  final item = await (db.select(db.saleItems)
        ..where((t) => t.saleId.equals(saleId))).getSingle();
  return LocalSaleReturnService(db, const UuidV7Generator(),
          clock: () => _t.add(const Duration(minutes: 1)))
      .create(SaleReturnDraft(
    shopId: 'shop', originalSaleId: saleId, ownerId: 'owner',
    deviceId: 'device', refundMethod: PaymentMethod.cash, reason: 'damaged',
    lines: [SaleReturnLineDraft(originalSaleItemId: item.id, quantity: 1000)],
  ));
}

Future<SyncOperation> _op(AppDatabase db, String id) =>
    (db.select(db.syncOperations)..where((t) => t.id.equals(id))).getSingle();

void main() {
  group('A-1 a void or return waits for its sale upload', () {
    late AppDatabase db;
    late SyncQueueRepository queue;
    setUp(() async {
      db = await _shop();
      queue = SyncQueueRepository(db, shopId: 'shop');
    });
    tearDown(() => db.close());

    test('void is not leased while its sale is in retry backoff', () async {
      final sale = await _sell(db);
      final voidId = await _void(db, sale.saleId);
      final voidOp = await (db.select(db.syncOperations)
            ..where((t) => t.entityId.equals(voidId))).getSingle();
      expect(voidOp.dependsOnOperationId, sale.syncOperationId);

      final now = _t.add(const Duration(minutes: 2));
      final first = await queue.acquireLease(workerId: 'w', now: now);
      expect(first!.id, sale.syncOperationId);
      // The sale upload hits a transient server error and waits to retry.
      await queue.failLease(
        id: first.id, workerId: 'w', error: 'HTTP 503', now: now,
        failure: classifySyncError(const _Coded('503')),
      );
      // Before this fix the void was handed out here and the cloud
      // answered "original sale required" until it needed attention.
      expect(await queue.acquireLease(workerId: 'w', now: now), isNull);

      final later = now.add(const Duration(minutes: 10));
      final retry = await queue.acquireLease(workerId: 'w', now: later);
      expect(retry!.id, sale.syncOperationId);
      await queue.completeLease(id: retry.id, workerId: 'w', now: later);
      final next = await queue.acquireLease(workerId: 'w', now: later);
      expect(next!.id, voidOp.id);
    });

    test('return depends on its unsynced sale; none once the sale synced',
        () async {
      final sale = await _sell(db);
      final first = await _return(db, sale.saleId);
      expect(
        (await _op(db, first.operationId)).dependsOnOperationId,
        sale.syncOperationId,
      );

      final now = _t.add(const Duration(minutes: 2));
      final leased = await queue.acquireLease(workerId: 'w', now: now);
      await queue.completeLease(id: leased!.id, workerId: 'w', now: now);
      final second = await _return(db, sale.saleId);
      expect((await _op(db, second.operationId)).dependsOnOperationId, isNull);
    });

    test('a parent operation that no longer exists does not block', () async {
      await db.into(db.syncOperations).insert(SyncOperationsCompanion.insert(
        id: 'orphan', shopId: 'shop', deviceId: 'device',
        entityType: 'sale_void', entityId: 'v',
        operationType: SyncOperationType.create, payload: '{}',
        dependsOnOperationId: const Value('pruned-parent'),
        createdAt: _t, updatedAt: _t,
      ));
      final leased = await queue.acquireLease(workerId: 'w', now: _t);
      expect(leased?.id, 'orphan');
    });
  });

  test('A-2 a sale with two returns refuses a void with the real reason',
      () async {
    final db = await _shop();
    addTearDown(db.close);
    final sale = await _sell(db);
    await _return(db, sale.saleId);
    await _return(db, sale.saleId);
    await expectLater(
      _void(db, sale.saleId),
      throwsA(isA<StateError>().having(
        (e) => e.message, 'message', 'A sale with returns cannot be voided.',
      )),
    );
  });

  group('A-3 POS cart follows refreshed prices', () {
    const old = PosProduct(
      id: 'surf', name: 'Surf', salePriceMinor: 35000,
      stockQuantity: 10000, stockTrackingEnabled: true,
    );
    const fresh = PosProduct(
      id: 'surf', name: 'Surf', salePriceMinor: 40000,
      stockQuantity: 9000, stockTrackingEnabled: true,
    );

    test('refreshProducts re-binds lines and keeps unknown ones', () {
      const gone = PosProduct(
        id: 'gone', name: 'Gone', salePriceMinor: 1000,
        stockQuantity: 0, stockTrackingEnabled: false,
      );
      final cart = PosCart()
        ..addQuantity(old, 2000)
        ..add(gone);
      cart.refreshProducts([fresh]);
      expect(cart.quantityOf('surf'), 2000);
      expect(cart.subtotalMinor, 2 * 40000 + 1000);
      expect(cart.lines.first.product.stockQuantity, 9000);
    });

    testWidgets('the workspace reloads the catalog after a background pull',
        (tester) async {
      tester.view.physicalSize = const Size(1340, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      final pulled = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        home: PosWorkspace(
          shopName: 'Ali Shop',
          cashierName: 'Ahmed',
          initialCatalog: const PosCatalogSnapshot(
            products: [old], categories: [], customers: [],
          ),
          committer: _Committer(
            const PosCatalogSnapshot(
              products: [fresh], categories: [], customers: [],
            ),
          ),
          salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
          offline: false,
          initialHasPendingSync: false,
          onLogout: () async {},
          catalogRefresh: pulled.future,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('Surf').first);
      await tester.pump();
      expect(find.textContaining('350.00'), findsWidgets);

      pulled.complete();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('400.00'), findsWidgets);
      // B-4: the old price now appears only in the price-change notice.
      final notice = find.byKey(const ValueKey('cart-price-changes'));
      expect(notice, findsOneWidget);
      expect(
        find.textContaining('350.00'),
        findsNWidgets(
          find
              .descendant(of: notice, matching: find.textContaining('350.00'))
              .evaluate()
              .length,
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(db.close);
    });
  });

  testWidgets('A-4 Receive payment is disabled while a payment is in flight',
      (tester) async {
    final actions = _KhataActions();
    await tester.pumpWidget(MaterialApp(
      home: CustomerDetailPage(
        customer: const CustomerAccount(
          id: 'c', name: 'Bilal', isActive: true, balanceMinor: 100000,
          totalCreditMinor: 100000, totalPaymentsMinor: 0,
        ),
        actions: actions,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive Payment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '300');
    await tester.tap(find.text('Record Payment'));
    await tester.pumpAndSettle();

    expect(actions.calls, 1);
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.onPressed, isNull);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Record Payment'), findsNothing);

    actions.release.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNotNull,
    );
    expect(actions.calls, 1);
  });

  test('A-5 an upload that never answers is cut and retried later', () async {
    final db = await _shop();
    addTearDown(db.close);
    final sale = await _sell(db);
    final result = await SyncWorker(
      queue: SyncQueueRepository(db, shopId: 'shop'),
      gateway: _HangingGateway(),
      workerId: 'w',
      uploadTimeout: const Duration(milliseconds: 50),
      clock: () => _t,
    ).runOnce();
    expect(result.failed, 1);
    final op = await _op(db, sale.syncOperationId);
    expect(op.status, SyncStatus.failed);
    expect(op.errorClass, SyncFailureKind.connectivity.name);
  });

  test('A-6 long digit runs are rejected, not overflowed', () {
    expect(parseMoneyMinor('999999999999.99'), 99999999999999);
    expect(parseMoneyMinor('9' * 13), isNull);
    expect(parseMoneyMinor('9' * 25), isNull);
    expect(products.parseQuantity('9' * 25), isNull);
    expect(purchases.parseQuantity('9' * 25), isNull);
    expect(products.parseQuantity('123456789.5'), 123456789500);
  });

  group('B-2 POS list limits', () {
    test('the catalog loads at most the limits and reports the real counts',
        () async {
      final db = await _shop();
      addTearDown(db.close);
      await db.batch((b) {
        for (var i = 0; i < posProductLimit; i++) {
          b.insert(db.shopProducts, ShopProductsCompanion.insert(
            id: 'p$i', shopId: 'shop', customName: Value('Item $i'),
            purchasePrice: 100, salePrice: 200, createdAt: _t, updatedAt: _t,
          ));
        }
        for (var i = 0; i <= posCustomerLimit; i++) {
          b.insert(db.customers, CustomersCompanion.insert(
            id: 'c$i', shopId: 'shop', name: 'Customer $i',
            createdAt: _t, updatedAt: _t,
          ));
        }
      });
      final snapshot = await DriftPosCatalog(db, shopId: 'shop').load();
      expect(snapshot.products, hasLength(posProductLimit));
      expect(snapshot.activeProductCount, posProductLimit + 1, reason: '+ Surf');
      expect(snapshot.productsTruncated, isTrue);
      expect(snapshot.customers, hasLength(posCustomerLimit));
      expect(snapshot.activeCustomerCount, posCustomerLimit + 1);
      expect(snapshot.customersTruncated, isTrue);
    });

    test('a catalog under the limits is not flagged and runs no count',
        () async {
      final db = await _shop();
      addTearDown(db.close);
      final snapshot = await DriftPosCatalog(db, shopId: 'shop').load();
      expect(snapshot.activeProductCount, isNull);
      expect(snapshot.productsTruncated, isFalse);
      expect(snapshot.customersTruncated, isFalse);
    });

    for (final urdu in [false, true]) {
      testWidgets('${urdu ? 'Urdu' : 'English'}: the cut is shown on the sale '
          'screen and in the Udhaar picker', (tester) async {
        tester.view.physicalSize = const Size(1340, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final l10n = lookupAppLocalizations(Locale(urdu ? 'ur' : 'en'));
        const product = PosProduct(
          id: 'surf', name: 'Surf', salePriceMinor: 35000,
          stockQuantity: 10000, stockTrackingEnabled: true,
        );
        final db = AppDatabase(NativeDatabase.memory());
        await tester.pumpWidget(LocalizedMaterialApp(
          controller: LocaleController(
            initialLocale:
                urdu ? LocaleController.urdu : LocaleController.english,
          ),
          home: PosWorkspace(
            shopName: 'Ali Shop',
            cashierName: 'Ahmed',
            initialCatalog: const PosCatalogSnapshot(
              products: [product], categories: [],
              customers: [PosCustomer(id: 'c', name: 'Bilal', balanceMinor: 0)],
              activeProductCount: 5200, activeCustomerCount: 1300,
            ),
            committer: _Committer(const PosCatalogSnapshot(
              products: [product], categories: [], customers: [],
            )),
            salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
            offline: false,
            initialHasPendingSync: false,
            onLogout: () async {},
          ),
        ));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(l10n.posCatalogTruncated('1', '5200')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(LocalizedMaterialApp(
          controller: LocaleController(
            initialLocale:
                urdu ? LocaleController.urdu : LocaleController.english,
          ),
          home: const Scaffold(
            body: PaymentDialog(
              totalMinor: 35000,
              customers: [PosCustomer(id: 'c', name: 'Bilal', balanceMinor: 0)],
              activeCustomerCount: 1300,
            ),
          ),
        ));
        await tester.pump();
        await tester.tap(find.text(l10n.paymentUdhaar).first);
        await tester.pump();
        expect(
          find.text(l10n.posCustomersTruncated('1', '1300')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        await tester.runAsync(db.close);
      });
    }
  });
}

final class _Coded implements SyncCodedError {
  const _Coded(this.code);
  @override
  final String code;
}

final class _HangingGateway implements SaleUploadGateway {
  @override
  Future<Object?> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) => Completer<Object?>().future;
}

final class _KhataActions implements CustomerKhataActions {
  var calls = 0;
  final release = Completer<void>();
  @override
  Future<List<CustomerAccount>> searchCustomers(String query) async => [];
  @override
  Future<List<CustomerLedgerLine>> statement(String customerId) async => [];
  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) {
    calls++;
    return release.future;
  }
}

final class _Committer implements PosSaleCommitter {
  _Committer(this.reloaded);
  final PosCatalogSnapshot reloaded;
  @override
  Future<CreatedSale> complete(
    String checkoutId,
    PosCart cart,
    PosPaymentPlan payment,
  ) => throw UnimplementedError();
  @override
  Future<PosCatalogSnapshot> reloadCatalog() async => reloaded;
  @override
  Future<bool> triggerSync() async => false;
  @override
  Stream<SyncHealth> watchSyncHealth() => Stream.value(SyncHealth.synced);
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
  Future<List<CustomerLedgerLine>> statement(String id) async => [];
}
