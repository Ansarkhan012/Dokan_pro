import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/shop_product_repository.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 9, 11);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final id in ['shop-a', 'shop-b']) {
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(
              id: id,
              name: 'Shop $id',
              phone: '03000000000',
              address: 'Karachi',
              subscriptionPlan: SubscriptionPlan.trial,
              subscriptionStatus: SubscriptionStatus.trial,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await db
        .into(db.devices)
        .insert(
          DevicesCompanion.insert(
            id: 'device-a',
            shopId: 'shop-a',
            deviceName: 'Counter',
            deviceType: DeviceType.windowsDesktop,
            deviceIdentifier: 'machine-a',
            createdAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  test('important local product CRUD is tenant scoped', () async {
    final a = ShopProductRepository(db, shopId: 'shop-a');
    final b = ShopProductRepository(db, shopId: 'shop-b');
    await a.save(
      ShopProductsCompanion.insert(
        id: 'product-a',
        shopId: 'shop-a',
        customName: const Value('Tea'),
        barcode: const Value('123'),
        purchasePrice: 10000,
        salePrice: 12000,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(await a.findByBarcode('123'), isNotNull);
    expect(await b.findByBarcode('123'), isNull);
    expect(
      () => b.save(
        ShopProductsCompanion.insert(
          id: 'invalid',
          shopId: 'shop-a',
          customName: const Value('Bad'),
          purchasePrice: 1,
          salePrice: 1,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsStateError,
    );
  });

  test('sale item keeps historical product snapshots', () async {
    await db
        .into(db.shopProducts)
        .insert(
          ShopProductsCompanion.insert(
            id: 'product-a',
            shopId: 'shop-a',
            customName: const Value('Coke'),
            barcode: const Value('999'),
            purchasePrice: 15000,
            salePrice: 18000,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: 'sale-a',
            shopId: 'shop-a',
            cashierId: 'cashier-a',
            deviceId: 'device-a',
            subtotal: 18000,
            discountTotal: 0,
            taxTotal: 0,
            grandTotal: 18000,
            paymentStatus: PaymentStatus.paid,
            saleStatus: SaleStatus.completed,
            createdAt: now,
          ),
        );
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            id: 'item-a',
            shopId: 'shop-a',
            saleId: 'sale-a',
            productId: 'product-a',
            productNameSnapshot: 'Coke',
            barcodeSnapshot: const Value('999'),
            quantity: 1000,
            costPriceSnapshot: 15000,
            salePriceSnapshot: 18000,
            discountAmount: 0,
            lineTotal: 18000,
            createdAt: now,
          ),
        );
    await (db.update(db.shopProducts)..where((t) => t.id.equals('product-a')))
        .write(const ShopProductsCompanion(salePrice: Value(19000)));
    final item = await db.select(db.saleItems).getSingle();
    expect(item.productNameSnapshot, 'Coke');
    expect(item.salePriceSnapshot, 18000);
  });

  test('sync queue follows retry and success transitions', () async {
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            id: 'op-stable-id',
            shopId: 'shop-a',
            deviceId: 'device-a',
            entityType: 'sale',
            entityId: 'sale-a',
            operationType: SyncOperationType.create,
            payload: '{"id":"sale-a"}',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final queue = SyncQueueRepository(db, shopId: 'shop-a');
    expect((await queue.pending()).single.id, 'op-stable-id');
    await queue.markSyncing('op-stable-id');
    await queue.markFailed('op-stable-id', 'offline');
    expect((await db.select(db.syncOperations).getSingle()).retryCount, 1);
    await queue.markSynced('op-stable-id', now.add(const Duration(minutes: 1)));
    expect(
      (await db.select(db.syncOperations).getSingle()).status,
      SyncStatus.synced,
    );
    expect(
      () => db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: 'op-stable-id',
              shopId: 'shop-a',
              deviceId: 'device-a',
              entityType: 'sale',
              entityId: 'sale-a',
              operationType: SyncOperationType.create,
              payload: '{}',
              createdAt: now,
              updatedAt: now,
            ),
          ),
      throwsA(anything),
    );
  });
}
