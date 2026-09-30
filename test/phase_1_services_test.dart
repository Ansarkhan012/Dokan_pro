import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/auth/domain/auth_state.dart';
import 'package:dukaan_pro/core/device/app_device_id.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/shop/domain/shop_membership.dart';
import 'package:dukaan_pro/features/shop/shop_bootstrap_gateway.dart';
import 'package:dukaan_pro/features/shop/shop_bootstrap_service.dart';
import 'package:dukaan_pro/sync/sale_sync_coordinator.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authentication identity maps signed-out and authenticated states', () {
    expect(mapAuthIdentity().status, AppAuthStatus.signedOut);
    final state = mapAuthIdentity(userId: 'user-a', email: 'a@example.test');
    expect(state.status, AppAuthStatus.authenticated);
    expect(state.userId, 'user-a');
  });

  test(
    'shop bootstrap detects no membership and resolves first shop',
    () async {
      final gateway = _FakeBootstrap();
      expect(
        await ShopBootstrapService(gateway).resolve(),
        isA<NeedsShopCreation>(),
      );
      gateway.rows.add(
        const ShopMembership(
          shopId: 'shop-a',
          shopName: 'A',
          role: ShopRole.owner,
        ),
      );
      expect(await ShopBootstrapService(gateway).resolve(), isA<ShopReady>());
    },
  );

  test('app-scoped device ID is generated once and remains stable', () async {
    final store = _MemoryDeviceStore();
    final ids = _SequenceIds();
    final provider = AppDeviceIdProvider(store, ids);
    expect(await provider.getOrCreate(), 'id-1');
    expect(await provider.getOrCreate(), 'id-1');
    expect(ids.calls, 1);
  });

  group('atomic local sale', () {
    late AppDatabase db;
    late _SequenceIds ids;
    late LocalSaleService service;
    final now = DateTime.utc(2026, 9, 12, 10);
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      ids = _SequenceIds();
      service = LocalSaleService(db, ids, clock: () => now);
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(
              id: 'shop-a',
              name: 'A',
              phone: '',
              address: '',
              subscriptionPlan: SubscriptionPlan.trial,
              subscriptionStatus: SubscriptionStatus.trial,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.shopUsers)
          .insert(
            ShopUsersCompanion.insert(
              id: 'member-a',
              shopId: 'shop-a',
              userId: 'owner-a',
              role: ShopRole.owner,
              createdAt: now,
            ),
          );
      await db
          .into(db.devices)
          .insert(
            DevicesCompanion.insert(
              id: 'device-a',
              shopId: 'shop-a',
              deviceName: 'Counter',
              deviceType: DeviceType.windowsDesktop,
              deviceIdentifier: 'app-uuid',
              createdAt: now,
            ),
          );
      await db
          .into(db.shopProducts)
          .insert(
            ShopProductsCompanion.insert(
              id: 'coke',
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
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'customer-a',
              shopId: 'shop-a',
              name: 'Ahmed',
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
    tearDown(() => db.close());

    SaleDraft draft({List<SalePaymentDraft>? payments, String? customerId}) =>
        SaleDraft(
          shopId: 'shop-a',
          cashierId: 'owner-a',
          deviceId: 'device-a',
          customerId: customerId,
          lines: const [SaleLineDraft(productId: 'coke', quantity: 2000)],
          payments:
              payments ??
              const [
                SalePaymentDraft(
                  method: PaymentMethod.cash,
                  amountMinor: 36000,
                ),
              ],
        );

    test(
      'split/credit sale creates complete aggregate and snapshots',
      () async {
        final result = await service.createSale(
          draft(
            customerId: 'customer-a',
            payments: const [
              SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 16000),
              SalePaymentDraft(
                method: PaymentMethod.credit,
                amountMinor: 20000,
              ),
            ],
          ),
        );
        expect(result.grandTotalMinor, 36000);
        expect(await db.select(db.sales).get(), hasLength(1));
        expect(await db.select(db.salePayments).get(), hasLength(2));
        final movement = await db.select(db.inventoryMovements).getSingle();
        expect(movement.quantity, -2000);
        final ledger = await db.select(db.customerLedgerEntries).getSingle();
        expect(ledger.amount, 20000);
        expect(ledger.type, CustomerLedgerType.creditSale);
        expect(await db.select(db.auditLogs).get(), hasLength(1));
        final operation = await db.select(db.syncOperations).getSingle();
        expect(operation.entityId, result.saleId);
        expect(operation.payload, contains('sale_items'));
        final payload = jsonDecode(operation.payload) as Map<String, dynamic>;
        final salePayload = payload['sale']! as Map<String, dynamic>;
        expect(salePayload['createdAt'], isA<String>());
        expect(
          DateTime.tryParse(salePayload['createdAt']! as String),
          isA<DateTime>(),
        );
        await (db.update(
          db.shopProducts,
        )..where((t) => t.id.equals('coke'))).write(
          const ShopProductsCompanion(
            customName: Value('New Coke'),
            salePrice: Value(19000),
          ),
        );
        final snapshot = await db.select(db.saleItems).getSingle();
        expect(snapshot.productNameSnapshot, 'Coke');
        expect(snapshot.salePriceSnapshot, 18000);
      },
    );

    test('invalid payment rolls back every write', () async {
      await expectLater(
        service.createSale(
          draft(
            payments: const [
              SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 1),
            ],
          ),
        ),
        throwsA(isA<SaleValidationException>()),
      );
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.inventoryMovements).get(), isEmpty);
      expect(await db.select(db.syncOperations).get(), isEmpty);
    });

    test('credit requires an active customer and rolls back', () async {
      await expectLater(
        service.createSale(
          draft(
            payments: const [
              SalePaymentDraft(
                method: PaymentMethod.credit,
                amountMinor: 36000,
              ),
            ],
          ),
        ),
        throwsA(isA<SaleValidationException>()),
      );
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.customerLedgerEntries).get(), isEmpty);
    });

    test(
      'split payment posts only the Udhaar portion and enforces credit limit',
      () async {
        await (db.update(db.customers)..where((t) => t.id.equals('customer-a')))
            .write(const CustomersCompanion(creditLimit: Value(25000)));
        final result = await service.createSale(
          draft(
            customerId: 'customer-a',
            payments: const [
              SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 16000),
              SalePaymentDraft(
                method: PaymentMethod.credit,
                amountMinor: 20000,
              ),
            ],
          ),
        );
        expect(result.grandTotalMinor, 36000);
        expect(
          (await db.select(db.customerLedgerEntries).getSingle()).amount,
          20000,
        );
        await expectLater(
          service.createSale(
            draft(
              customerId: 'customer-a',
              payments: const [
                SalePaymentDraft(
                  method: PaymentMethod.credit,
                  amountMinor: 36000,
                ),
              ],
            ),
          ),
          throwsA(isA<SaleValidationException>()),
        );
        expect(await db.select(db.sales).get(), hasLength(1));
      },
    );

    test('retry retains operation and sale identifiers', () async {
      final created = await service.createSale(draft());
      final gateway = _FailOnceGateway();
      final coordinator = SaleSyncCoordinator(
        SyncQueueRepository(db, shopId: 'shop-a'),
        gateway,
        clock: () => now,
      );
      expect(await coordinator.upload(created.syncOperationId), isFalse);
      final failed = await db.select(db.syncOperations).getSingle();
      expect(failed.entityId, created.saleId);
      expect(failed.retryCount, 1);
      expect(await coordinator.upload(created.syncOperationId), isTrue);
      final synced = await db.select(db.syncOperations).getSingle();
      expect(synced.id, created.syncOperationId);
      expect(synced.entityId, created.saleId);
      expect(synced.status, SyncStatus.synced);
    });
  });
}

final class _FakeBootstrap implements ShopBootstrapGateway {
  final rows = <ShopMembership>[];
  @override
  Future<List<ShopMembership>> memberships() async => rows;
  @override
  Future<ShopMembership> createOwnerShop({
    required String name,
    required String phone,
    required String address,
  }) async =>
      ShopMembership(shopId: 'created', shopName: name, role: ShopRole.owner);
}

final class _MemoryDeviceStore implements DeviceIdStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

final class _SequenceIds implements IdGenerator {
  int calls = 0;
  @override
  String next() => 'id-${++calls}';
}

final class _FailOnceGateway implements SaleUploadGateway {
  int calls = 0;
  @override
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) async {
    if (++calls == 1) throw Exception('offline');
  }
}
