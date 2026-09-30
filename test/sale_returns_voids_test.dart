import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final soldAt = DateTime.utc(2026, 9, 20, 10);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
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
            createdAt: soldAt,
            updatedAt: soldAt,
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
            createdAt: soldAt,
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
            deviceIdentifier: 'identifier',
            createdAt: soldAt,
          ),
        );
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'customer',
            shopId: 'shop',
            name: 'Ahmed',
            createdAt: soldAt,
            updatedAt: soldAt,
          ),
        );
    await db
        .into(db.shopProducts)
        .insert(
          ShopProductsCompanion.insert(
            id: 'product',
            shopId: 'shop',
            customName: const Value('Rice'),
            purchasePrice: 10000,
            salePrice: 12000,
            createdAt: soldAt,
            updatedAt: soldAt,
          ),
        );
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: 'sale',
            shopId: 'shop',
            cashierId: 'owner',
            customerId: const Value('customer'),
            deviceId: 'device',
            subtotal: 12000,
            discountTotal: 0,
            taxTotal: 0,
            grandTotal: 12000,
            paymentStatus: PaymentStatus.paid,
            saleStatus: SaleStatus.completed,
            createdAt: soldAt,
          ),
        );
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            id: 'item',
            shopId: 'shop',
            saleId: 'sale',
            productId: 'product',
            productNameSnapshot: 'Rice',
            quantity: 1000,
            costPriceSnapshot: 10000,
            salePriceSnapshot: 12000,
            discountAmount: 0,
            lineTotal: 12000,
            createdAt: soldAt,
          ),
        );
    await db
        .into(db.salePayments)
        .insert(
          SalePaymentsCompanion.insert(
            id: 'payment',
            saleId: 'sale',
            shopId: 'shop',
            paymentMethod: PaymentMethod.credit,
            amount: 12000,
            createdAt: soldAt,
          ),
        );
    await db
        .into(db.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: 'sale-movement',
            shopId: 'shop',
            productId: 'product',
            type: InventoryMovementType.sale,
            quantity: -1000,
            referenceType: const Value('sale'),
            referenceId: const Value('sale'),
            createdBy: 'owner',
            deviceId: const Value('device'),
            createdAt: soldAt,
          ),
        );
    await db
        .into(db.customerLedgerEntries)
        .insert(
          CustomerLedgerEntriesCompanion.insert(
            id: 'debt',
            shopId: 'shop',
            customerId: 'customer',
            type: CustomerLedgerType.creditSale,
            amount: 12000,
            saleId: const Value('sale'),
            createdBy: 'owner',
            createdAt: soldAt,
          ),
        );
  });
  tearDown(() => db.close());

  test(
    'partial credit return is append-only, restores stock and reduces debt',
    () async {
      final result =
          await LocalSaleReturnService(
            db,
            _Ids(),
            clock: () => soldAt.add(const Duration(minutes: 20)),
          ).create(
            const SaleReturnDraft(
              shopId: 'shop',
              originalSaleId: 'sale',
              ownerId: 'owner',
              deviceId: 'device',
              refundMethod: PaymentMethod.credit,
              reason: 'Customer returned half',
              lines: [
                SaleReturnLineDraft(originalSaleItemId: 'item', quantity: 500),
              ],
            ),
          );
      expect(result.refundAmount, 6000);
      expect(
        (await db.select(db.sales).getSingle()).saleStatus,
        SaleStatus.completed,
      );
      expect(
        (await db.select(db.inventoryMovements).get())
            .map((x) => x.quantity)
            .fold(0, (a, b) => a + b),
        -500,
      );
      final ledger = await db.select(db.customerLedgerEntries).get();
      expect(
        ledger
            .map((x) => x.type.balanceSign * x.amount)
            .fold(0, (a, b) => a + b),
        6000,
      );
      expect(await db.select(db.auditLogs).get(), hasLength(1));
      expect(await db.select(db.syncOperations).get(), hasLength(1));
    },
  );

  test('cannot return beyond the immutable sold quantity', () async {
    final service = LocalSaleReturnService(
      db,
      _Ids(),
      clock: () => soldAt.add(const Duration(minutes: 20)),
    );
    await service.create(
      const SaleReturnDraft(
        shopId: 'shop',
        originalSaleId: 'sale',
        ownerId: 'owner',
        deviceId: 'device',
        refundMethod: PaymentMethod.credit,
        reason: 'First half',
        lines: [SaleReturnLineDraft(originalSaleItemId: 'item', quantity: 500)],
      ),
    );
    await expectLater(
      service.create(
        const SaleReturnDraft(
          shopId: 'shop',
          originalSaleId: 'sale',
          ownerId: 'owner',
          deviceId: 'device',
          refundMethod: PaymentMethod.credit,
          reason: 'Too much',
          lines: [
            SaleReturnLineDraft(originalSaleItemId: 'item', quantity: 501),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.select(db.saleReturns).get(), hasLength(1));
  });

  test('void is owner-only, time limited and compensating', () async {
    await LocalSaleVoidService(
      db,
      _Ids(),
      clock: () => soldAt.add(const Duration(minutes: 10)),
    ).voidSale(
      shopId: 'shop',
      saleId: 'sale',
      ownerId: 'owner',
      deviceId: 'device',
      reason: 'Wrong bill',
    );
    expect(await db.select(db.saleVoids).get(), hasLength(1));
    expect(
      (await db.select(db.sales).getSingle()).saleStatus,
      SaleStatus.completed,
    );
    expect(
      (await db.select(db.inventoryMovements).get())
          .map((x) => x.quantity)
          .fold(0, (a, b) => a + b),
      0,
    );
    await expectLater(
      LocalSaleVoidService(
        db,
        _Ids(),
        clock: () => soldAt.add(const Duration(minutes: 30)),
      ).voidSale(
        shopId: 'shop',
        saleId: 'sale',
        ownerId: 'owner',
        deviceId: 'device',
        reason: 'Late',
      ),
      throwsA(isA<StateError>()),
    );
  });
}

final class _Ids implements IdGenerator {
  var i = 0;
  @override
  String next() =>
      '00000000-0000-7000-8000-${(++i).toString().padLeft(12, '0')}';
}
