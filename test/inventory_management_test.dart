import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/inventory/drift_inventory_repository.dart';
import 'package:dukaan_pro/features/inventory/inventory_models.dart';
import 'package:dukaan_pro/features/inventory/local_inventory_adjustment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LocalInventoryAdjustmentService service;
  final now = DateTime.utc(2026, 9, 16);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = LocalInventoryAdjustmentService(db, _Ids(), clock: () => now);
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(
            id: 'shop',
            name: 'Shop',
            phone: '',
            address: '',
            subscriptionPlan: SubscriptionPlan.trial,
            subscriptionStatus: SubscriptionStatus.trial,
            allowNegativeStock: const Value(false),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.shopUsers)
        .insert(
          ShopUsersCompanion.insert(
            id: 'membership',
            shopId: 'shop',
            userId: 'owner',
            role: ShopRole.owner,
            createdAt: now,
          ),
        );
    await db
        .into(db.devices)
        .insert(
          DevicesCompanion.insert(
            id: 'device',
            shopId: 'shop',
            deviceName: 'Counter',
            deviceType: DeviceType.windowsDesktop,
            deviceIdentifier: 'counter-1',
            createdAt: now,
          ),
        );
    await db
        .into(db.shopProducts)
        .insert(
          ShopProductsCompanion.insert(
            id: 'product',
            shopId: 'shop',
            customName: const Value('Rice'),
            unit: const Value('kg'),
            purchasePrice: 10000,
            salePrice: 12000,
            lowStockLevel: const Value(2000),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });
  tearDown(() => db.close());

  test(
    'adjustments append movements, audit, and pending operation atomically',
    () async {
      await service.record(
        shopId: 'shop',
        productId: 'product',
        ownerId: 'owner',
        deviceId: 'device',
        type: InventoryMovementType.openingStock,
        quantity: 5000,
        note: 'Counted opening stock',
      );
      await service.record(
        shopId: 'shop',
        productId: 'product',
        ownerId: 'owner',
        deviceId: 'device',
        type: InventoryMovementType.damage,
        quantity: 1000,
        note: 'Damaged bag',
      );
      final row = (await DriftInventoryRepository(
        db,
        shopId: 'shop',
      ).products()).single;
      expect(row.stockQuantity, 4000);
      expect(await db.select(db.inventoryMovements).get(), hasLength(2));
      expect(await db.select(db.auditLogs).get(), hasLength(2));
      final operations = await db.select(db.syncOperations).get();
      expect(operations, hasLength(2));
      expect(operations.every((x) => x.status == SyncStatus.pending), isTrue);
    },
  );

  test('negative stock policy and shop isolation are enforced', () async {
    await expectLater(
      service.record(
        shopId: 'shop',
        productId: 'product',
        ownerId: 'owner',
        deviceId: 'device',
        type: InventoryMovementType.damage,
        quantity: 1000,
        note: 'Damage',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.record(
        shopId: 'other',
        productId: 'product',
        ownerId: 'owner',
        deviceId: 'device',
        type: InventoryMovementType.manualAdjustment,
        quantity: 1000,
        note: 'Wrong shop',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('low and out-of-stock filters use ledger-derived stock', () async {
    final repository = DriftInventoryRepository(db, shopId: 'shop');
    expect(
      await repository.products(filter: InventoryFilter.outOfStock),
      hasLength(1),
    );
    await service.record(
      shopId: 'shop',
      productId: 'product',
      ownerId: 'owner',
      deviceId: 'device',
      type: InventoryMovementType.openingStock,
      quantity: 1000,
      note: 'Opening',
    );
    expect(
      await repository.products(filter: InventoryFilter.lowStock),
      hasLength(1),
    );
  });
}

final class _Ids implements IdGenerator {
  var value = 0;
  @override
  String next() =>
      '00000000-0000-7000-8000-${(++value).toString().padLeft(12, '0')}';
}
