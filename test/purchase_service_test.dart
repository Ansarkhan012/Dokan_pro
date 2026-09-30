import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/purchases/drift_purchase_repository.dart';
import 'package:dukaan_pro/features/purchases/local_purchase_service.dart';
import 'package:dukaan_pro/features/purchases/local_supplier_payment_service.dart';
import 'package:dukaan_pro/features/purchases/purchase_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late _Ids ids;
  final now = DateTime.utc(2026, 9, 14);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ids = _Ids();
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(
            id: 'shop',
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
            id: 'member',
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
            deviceName: 'PC',
            deviceType: DeviceType.windowsDesktop,
            deviceIdentifier: 'identifier',
            createdAt: now,
          ),
        );
    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: 'supplier',
            shopId: 'shop',
            name: 'Karachi Wholesale Traders',
            createdAt: now,
            updatedAt: now,
          ),
        );
    for (final p in [('sugar', 'Sugar', 16000), ('milk', 'Milk', 25000)]) {
      await db
          .into(db.shopProducts)
          .insert(
            ShopProductsCompanion.insert(
              id: p.$1,
              shopId: 'shop',
              customName: Value(p.$2),
              purchasePrice: p.$3,
              salePrice: p.$3 + 2000,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  });
  tearDown(() => db.close());
  PurchaseDraft draft({int paid = 185000}) => PurchaseDraft(
    shopId: 'shop',
    supplierId: 'supplier',
    deviceId: 'device',
    ownerId: 'owner',
    invoiceNumber: 'INV-184',
    lines: const [
      PurchaseLineDraft(
        productId: 'sugar',
        quantity: 10000,
        unitCostMinor: 16000,
      ),
      PurchaseLineDraft(
        productId: 'milk',
        quantity: 5000,
        unitCostMinor: 25000,
      ),
    ],
    payments: paid == 0
        ? const []
        : [PurchasePaymentDraft(method: PaymentMethod.cash, amountMinor: paid)],
  );
  test(
    'split purchase atomically posts stock and only unpaid payable',
    () async {
      final made = await LocalPurchaseService(
        db,
        ids,
        clock: () => now,
      ).create(draft());
      expect(made.totalMinor, 285000);
      expect(made.paidMinor, 185000);
      expect(made.dueMinor, 100000);
      expect(
        (await db.select(db.inventoryMovements).get()).map((e) => e.quantity),
        containsAll([10000, 5000]),
      );
      expect(
        (await db.select(db.supplierLedgerEntries).getSingle()).amount,
        100000,
      );
      expect(await db.select(db.purchasePayments).get(), hasLength(1));
      expect(await db.select(db.auditLogs).get(), hasLength(1));
      expect(
        jsonDecode(
          (await db.select(db.syncOperations).getSingle()).payload,
        )['operation'],
        'sync_purchase_transaction',
      );
    },
  );
  test('full cash creates no payable and full credit posts total', () async {
    await LocalPurchaseService(db, ids).create(draft(paid: 285000));
    expect(await db.select(db.supplierLedgerEntries).get(), isEmpty);
    await LocalPurchaseService(db, ids).create(draft(paid: 0));
    expect(
      (await db.select(db.supplierLedgerEntries).getSingle()).amount,
      285000,
    );
  });
  test('supplier payment reduces derived payable and queues', () async {
    await LocalPurchaseService(db, ids).create(draft());
    await LocalSupplierPaymentService(db, ids).record(
      shopId: 'shop',
      supplierId: 'supplier',
      ownerId: 'owner',
      deviceId: 'device',
      amountMinor: 40000,
      method: PaymentMethod.cash,
    );
    final account = (await DriftPurchaseRepository(
      db,
      shopId: 'shop',
    ).suppliers('Karachi')).single;
    expect(account.payableMinor, 60000);
    expect(account.totalPaymentsMinor, 40000);
    expect(await db.select(db.syncOperations).get(), hasLength(2));
  });
  test('supplier payment cannot exceed current payable', () async {
    await LocalPurchaseService(db, ids).create(draft());
    await expectLater(
      LocalSupplierPaymentService(db, ids).record(
        shopId: 'shop',
        supplierId: 'supplier',
        ownerId: 'owner',
        deviceId: 'device',
        amountMinor: 100001,
        method: PaymentMethod.cash,
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.supplierLedgerEntries).get(), hasLength(1));
  });
  test(
    'invalid or duplicate lines rollback and snapshots do not change',
    () async {
      await expectLater(
        LocalPurchaseService(db, ids).create(
          PurchaseDraft(
            shopId: 'shop',
            supplierId: 'supplier',
            deviceId: 'device',
            ownerId: 'owner',
            lines: const [
              PurchaseLineDraft(
                productId: 'sugar',
                quantity: 1000,
                unitCostMinor: 100,
              ),
              PurchaseLineDraft(
                productId: 'sugar',
                quantity: 1000,
                unitCostMinor: 100,
              ),
            ],
            payments: const [],
          ),
        ),
        throwsArgumentError,
      );
      expect(await db.select(db.purchases).get(), isEmpty);
      await LocalPurchaseService(db, ids).create(draft());
      await (db.update(
        db.shopProducts,
      )..where((t) => t.id.equals('sugar'))).write(
        const ShopProductsCompanion(
          customName: Value('New Sugar'),
          purchasePrice: Value(99999),
        ),
      );
      expect(
        (await db.select(db.purchaseItems).get())
            .firstWhere((e) => e.productId == 'sugar')
            .productNameSnapshot,
        'Sugar',
      );
    },
  );
}

final class _Ids implements IdGenerator {
  int n = 0;
  @override
  String next() =>
      '00000000-0000-7000-8000-${(++n).toString().padLeft(12, '0')}';
}
