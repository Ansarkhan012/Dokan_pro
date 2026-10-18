import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:dukaan_pro/auth/cashier_auth_gateway.dart';
import 'package:dukaan_pro/auth/cashier_session.dart';
import 'package:dukaan_pro/auth/cashier_session_manager.dart';
import 'package:dukaan_pro/auth/cashier_session_store.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // R1.2 (T-1): an offset-less string is a device wall clock, not UTC, so it
  // is refused instead of being relabelled with 'Z' (which shifted every sale
  // by the device offset). Epoch and explicit-offset forms keep their instant.
  test(
    'legacy queued sale timestamps: unambiguous forms normalize to UTC ISO-8601, offset-less text is refused',
    () {
      final normalized = normalizeSalePayloadForCloud({
        'sale': {'createdAt': 1789275188000, 'grandTotal': 19000},
        'sale_items': [
          {'createdAt': '2026-09-13T09:53:08.000+05:00'},
        ],
      });
      final sale = normalized['sale']! as Map<String, dynamic>;
      final items = normalized['sale_items']! as List<dynamic>;
      expect(sale['createdAt'], '2026-09-13T04:53:08.000Z');
      expect(
        (items.single as Map<String, dynamic>)['createdAt'],
        equals(sale['createdAt']),
      );
      expect(sale['grandTotal'], 19000);
      expect(
        () => normalizeSalePayloadForCloud({
          'sale': {'createdAt': '2026-09-13T04:53:08.000', 'grandTotal': 19000},
        }),
        throwsA(isA<AmbiguousTimestampPayload>()),
      );
    },
  );

  group('cashier local session policy', () {
    final now = DateTime.utc(2026, 9, 12, 12);
    test(
      'trusted login persists token and permits offline continuation until expiry',
      () async {
        final gateway = _CashierGateway(now);
        final store = _SessionStore();
        final manager = CashierSessionManager(gateway, store, clock: () => now);
        final session = await manager.login(
          shopId: 'shop-a',
          deviceIdentifier: 'app-device',
          cashierId: 'cashier-a',
          pin: '1234',
        );
        expect(session.token, 'raw-once-token');
        expect(await manager.canContinueOffline(), isTrue);
        expect(store.value?.cashierId, 'cashier-a');
      },
    );
    test('expired or server-revoked session is cleared', () async {
      final gateway = _CashierGateway(now)..valid = false;
      final store = _SessionStore()
        ..value = CashierSession(
          token: 't',
          shopId: 'shop-a',
          cashierId: 'cashier-a',
          deviceId: 'device-a',
          expiresAt: now.add(const Duration(hours: 1)),
        );
      final manager = CashierSessionManager(gateway, store, clock: () => now);
      expect(await manager.validateOnline(), isFalse);
      expect(store.value, isNull);
      store.value = CashierSession(
        token: 't',
        shopId: 'shop-a',
        cashierId: 'cashier-a',
        deviceId: 'device-a',
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );
      expect(await manager.canContinueOffline(), isFalse);
    });
    test('gateway validation is bound to stored shop and device', () async {
      final gateway = _CashierGateway(now);
      final store = _SessionStore();
      final session = CashierSession(
        token: 't',
        shopId: 'shop-a',
        cashierId: 'cashier-a',
        deviceId: 'device-a',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      store.value = session;
      gateway.expectedDevice = 'device-b';
      expect(
        await CashierSessionManager(
          gateway,
          store,
          clock: () => now,
        ).validateOnline(),
        isFalse,
      );
    });
    test('cached cashier from another shop is destroyed', () async {
      final store = _SessionStore()
        ..value = CashierSession(
          token: 't',
          shopId: 'shop-b',
          cashierId: 'cashier-b',
          deviceId: 'device-a',
          expiresAt: now.add(const Duration(hours: 1)),
        );
      final restored =
          await CashierSessionManager(
            _CashierGateway(now),
            store,
            clock: () => now,
          ).restoreForContext(
            shopId: 'shop-a',
            deviceId: 'device-a',
            hasRequiredLocalData: true,
          );
      expect(restored, isNull);
      expect(store.value, isNull);
    });
    test(
      'cached cashier for another device or missing local data is denied',
      () async {
        final store = _SessionStore()
          ..value = CashierSession(
            token: 't',
            shopId: 'shop-a',
            cashierId: 'cashier-a',
            deviceId: 'device-b',
            expiresAt: now.add(const Duration(hours: 1)),
          );
        final manager = CashierSessionManager(
          _CashierGateway(now),
          store,
          clock: () => now,
        );
        expect(
          await manager.restoreForContext(
            shopId: 'shop-a',
            deviceId: 'device-a',
            hasRequiredLocalData: true,
          ),
          isNull,
        );
        store.value = CashierSession(
          token: 't',
          shopId: 'shop-a',
          cashierId: 'cashier-a',
          deviceId: 'device-a',
          expiresAt: now.add(const Duration(hours: 1)),
        );
        expect(
          await manager.restoreForContext(
            shopId: 'shop-a',
            deviceId: 'device-a',
            hasRequiredLocalData: false,
          ),
          isNull,
        );
        expect(store.value, isNull);
      },
    );
    test(
      'explicit logout clears persisted token when server revoke fails',
      () async {
        final gateway = _CashierGateway(now)..throwOnRevoke = true;
        final store = _SessionStore()
          ..value = CashierSession(
            token: 'sensitive-token',
            shopId: 'shop-a',
            cashierId: 'cashier-a',
            deviceId: 'device-a',
            expiresAt: now.add(const Duration(hours: 1)),
          );
        await expectLater(
          CashierSessionManager(gateway, store, clock: () => now).logout(),
          throwsStateError,
        );
        expect(store.value, isNull);
      },
    );
  });

  group('durable queue leasing', () {
    late AppDatabase db;
    late SyncQueueRepository queue;
    final start = DateTime.utc(2026, 9, 12);
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
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
              createdAt: start,
              updatedAt: start,
            ),
          );
      await db
          .into(db.devices)
          .insert(
            DevicesCompanion.insert(
              id: 'device-a',
              shopId: 'shop-a',
              deviceName: 'D',
              deviceType: DeviceType.windowsDesktop,
              deviceIdentifier: 'identifier',
              createdAt: start,
            ),
          );
      queue = SyncQueueRepository(db, shopId: 'shop-a');
      await _insertOperation(db, 'op-a', start);
    });
    tearDown(() => db.close());
    test(
      'only one worker owns a live lease and expired lease recovers',
      () async {
        expect(
          (await queue.acquireLease(workerId: 'worker-1', now: start))?.id,
          'op-a',
        );
        expect(
          await queue.acquireLease(
            workerId: 'worker-2',
            now: start.add(const Duration(seconds: 1)),
          ),
          isNull,
        );
        expect(
          (await queue.acquireLease(
            workerId: 'worker-2',
            now: start.add(const Duration(minutes: 3)),
          ))?.id,
          'op-a',
        );
      },
    );
    test(
      'failure applies backoff and preserves stable operation identity',
      () async {
        final leased = await queue.acquireLease(workerId: 'worker', now: start);
        await queue.failLease(
          id: leased!.id,
          workerId: 'worker',
          error: 'offline',
          now: start,
        );
        expect(
          await queue.acquireLease(
            workerId: 'worker',
            now: start.add(const Duration(seconds: 1)),
          ),
          isNull,
        );
        final retry = await queue.acquireLease(
          workerId: 'worker',
          now: start.add(const Duration(seconds: 3)),
        );
        expect(retry?.id, 'op-a');
        expect(retry?.retryCount, 1);
      },
    );
    test('successful retry clears lease, error and retry schedule', () async {
      final first = await queue.acquireLease(workerId: 'worker', now: start);
      await queue.failLease(
        id: first!.id,
        workerId: 'worker',
        error: 'offline',
        now: start,
      );
      final retry = await queue.acquireLease(
        workerId: 'worker',
        now: start.add(const Duration(seconds: 3)),
      );
      await queue.completeLease(
        id: retry!.id,
        workerId: 'worker',
        now: start.add(const Duration(seconds: 4)),
      );
      final row = await db.select(db.syncOperations).getSingle();
      expect(row.status, SyncStatus.synced);
      expect(row.lastError, isNull);
      expect(row.nextAttemptAt, isNull);
      expect(row.leaseOwner, isNull);
      expect(row.leaseExpiresAt, isNull);
    });
  });

  group('deterministic reference pull', () {
    late AppDatabase db;
    final stamp = DateTime.utc(2026, 9, 12, 1);
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
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
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
    });
    tearDown(() => db.close());
    test(
      'insert, update, deactivate and equal timestamp UUID ordering',
      () async {
        final gateway = _PullGateway([
          _product('a-id', stamp, name: 'Coke', active: true),
          _product('b-id', stamp, name: 'Milk', active: true),
        ]);
        final service = ReferencePullService(db, gateway, shopId: 'shop-a');
        expect(await service.pull(PullEntity.shopProducts, pageSize: 1), 2);
        expect(await db.select(db.shopProducts).get(), hasLength(2));
        gateway.rows.add(
          _product(
            'a-id',
            stamp.add(const Duration(seconds: 1)),
            name: 'Coke 2',
            active: false,
          ),
        );
        expect(await service.pull(PullEntity.shopProducts), 1);
        final coke = await (db.select(
          db.shopProducts,
        )..where((t) => t.id.equals('a-id'))).getSingle();
        expect(coke.customName, 'Coke 2');
        expect(coke.isActive, isFalse);
      },
    );
    test(
      'foreign shop record is rejected and never enters local database',
      () async {
        final gateway = _PullGateway([
          _product(
            'foreign',
            stamp,
            name: 'Bad',
            active: true,
            shopId: 'shop-b',
          ),
        ]);
        await expectLater(
          ReferencePullService(
            db,
            gateway,
            shopId: 'shop-a',
          ).pull(PullEntity.shopProducts),
          throwsStateError,
        );
        expect(await db.select(db.shopProducts).get(), isEmpty);
        expect(await db.select(db.syncCursors).get(), isEmpty);
      },
    );
    test('inventory movement pull is durable and idempotent', () async {
      await db
          .into(db.shopProducts)
          .insert(
            ShopProductsCompanion.insert(
              id: 'product-a',
              shopId: 'shop-a',
              customName: const Value('Sugar'),
              purchasePrice: 100,
              salePrice: 200,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      final movement = RemoteChange(
        entity: PullEntity.inventoryMovements,
        id: 'movement-a',
        shopId: 'shop-a',
        updatedAt: stamp,
        data: {
          'id': 'movement-a',
          'shop_id': 'shop-a',
          'product_id': 'product-a',
          'type': 'openingStock',
          'quantity': 20000,
          'reference_type': 'development_seed',
          'reference_id': null,
          'note': null,
          'created_by': 'owner-a',
          'device_id': null,
          'created_at': stamp.toIso8601String(),
        },
      );
      final service = ReferencePullService(
        db,
        _PullGateway([movement]),
        shopId: 'shop-a',
      );
      expect(await service.pull(PullEntity.inventoryMovements), 1);
      expect(await service.pull(PullEntity.inventoryMovements), 0);
      final rows = await db.select(db.inventoryMovements).get();
      expect(rows, hasLength(1));
      expect(rows.single.quantity, 20000);
    });
    test('return pull is tenant scoped, ordered and idempotent', () async {
      final t = stamp.millisecondsSinceEpoch ~/ 1000;
      await db.customStatement(
        "insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at) values('device-a','shop-a','PC','windowsDesktop','dev-a',$t,$t)",
      );
      await db.customStatement(
        "insert into shop_products(id,shop_id,custom_name,purchase_price,sale_price,created_at,updated_at) values('product-a','shop-a','Tea',100,200,$t,$t)",
      );
      await db.customStatement(
        "insert into sales(id,shop_id,cashier_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at) values('sale-a','shop-a','cashier-a','device-a',200,0,0,200,'paid','completed',$t)",
      );
      await db.customStatement(
        "insert into sale_items(id,shop_id,sale_id,product_id,product_name_snapshot,quantity,cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at) values('item-a','shop-a','sale-a','product-a','Tea snapshot',1000,100,200,0,200,$t)",
      );
      final returned = RemoteChange(
        entity: PullEntity.saleReturns,
        id: 'return-a',
        shopId: 'shop-a',
        updatedAt: stamp,
        data: {
          'id': 'return-a',
          'shop_id': 'shop-a',
          'original_sale_id': 'sale-a',
          'customer_id': null,
          'device_id': 'device-a',
          'refund_method': 'cash',
          'refund_amount': 100,
          'reason': 'half',
          'created_by': 'owner-a',
          'created_at': stamp.toIso8601String(),
          'synced_at': stamp.toIso8601String(),
        },
      );
      final item = RemoteChange(
        entity: PullEntity.saleReturnItems,
        id: 'return-item-a',
        shopId: 'shop-a',
        updatedAt: stamp,
        data: {
          'id': 'return-item-a',
          'shop_id': 'shop-a',
          'return_id': 'return-a',
          'original_sale_item_id': 'item-a',
          'product_id': 'product-a',
          'product_name_snapshot': 'Tea snapshot',
          'quantity': 500,
          'unit_price_snapshot': 200,
          'refund_amount': 100,
          'created_at': stamp.toIso8601String(),
        },
      );
      final service = ReferencePullService(
        db,
        _PullGateway([returned, item]),
        shopId: 'shop-a',
      );
      expect(await service.pull(PullEntity.saleReturns), 1);
      expect(await service.pull(PullEntity.saleReturnItems), 1);
      expect(await service.pull(PullEntity.saleReturns), 0);
      expect(await db.select(db.saleReturns).get(), hasLength(1));
      expect(
        (await db.select(db.saleReturnItems).get()).single.productNameSnapshot,
        'Tea snapshot',
      );
    });
  });
}

Future<void> _insertOperation(AppDatabase db, String id, DateTime at) => db
    .into(db.syncOperations)
    .insert(
      SyncOperationsCompanion.insert(
        id: id,
        shopId: 'shop-a',
        deviceId: 'device-a',
        entityType: 'sale_aggregate',
        entityId: 'sale-a',
        operationType: SyncOperationType.create,
        payload: '{}',
        createdAt: at,
        updatedAt: at,
      ),
    );

final class _CashierGateway implements CashierAuthGateway {
  _CashierGateway(this.now);
  final DateTime now;
  bool valid = true;
  bool throwOnRevoke = false;
  String expectedDevice = 'device-a';
  @override
  Future<CashierSession> authenticate({
    required String shopId,
    required String deviceIdentifier,
    required String cashierId,
    required String pin,
  }) async {
    if (pin != '1234') throw StateError('invalid');
    return CashierSession(
      token: 'raw-once-token',
      shopId: shopId,
      cashierId: cashierId,
      deviceId: 'device-a',
      expiresAt: now.add(const Duration(hours: 12)),
    );
  }

  @override
  Future<bool> validate(CashierSession session) async =>
      valid && session.deviceId == expectedDevice && session.shopId == 'shop-a';
  @override
  Future<void> revoke(CashierSession session) async {
    if (throwOnRevoke) throw StateError('backend unavailable');
    valid = false;
  }
}

final class _SessionStore implements CashierSessionStore {
  CashierSession? value;
  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<CashierSession?> read() async => value;
  @override
  Future<void> write(CashierSession session) async {
    value = session;
  }
}

RemoteChange _product(
  String id,
  DateTime updatedAt, {
  required String name,
  required bool active,
  String shopId = 'shop-a',
}) => RemoteChange(
  entity: PullEntity.shopProducts,
  id: id,
  shopId: shopId,
  updatedAt: updatedAt,
  data: {
    'id': id,
    'shop_id': shopId,
    'master_product_id': null,
    'custom_name': name,
    'barcode': id,
    'purchase_price': 100,
    'sale_price': 200,
    'stock_tracking_enabled': true,
    'low_stock_level': 0,
    'is_active': active,
    'created_at': updatedAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  },
);

final class _PullGateway implements ReferencePullGateway {
  _PullGateway(this.rows);
  final List<RemoteChange> rows;
  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    final sorted =
        rows
            .where(
              (r) =>
                  r.entity == entity &&
                  (after == null ||
                      r.updatedAt.isAfter(after.updatedAt) ||
                      (r.updatedAt.compareTo(after.updatedAt) == 0 &&
                          r.id.compareTo(after.entityId) > 0)),
            )
            .toList()
          ..sort((a, b) {
            final byTime = a.updatedAt.compareTo(b.updatedAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    return sorted.take(limit).toList();
  }
}
