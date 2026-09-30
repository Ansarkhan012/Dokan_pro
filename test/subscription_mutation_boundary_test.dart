import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/local_customer_payment_service.dart';
import 'package:dukaan_pro/features/expenses/expense_models.dart';
import 'package:dukaan_pro/features/expenses/local_expense_service.dart';
import 'package:dukaan_pro/features/inventory/local_inventory_adjustment_service.dart';
import 'package:dukaan_pro/features/purchases/local_purchase_service.dart';
import 'package:dukaan_pro/features/purchases/local_supplier_payment_service.dart';
import 'package:dukaan_pro/features/purchases/purchase_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  const blocked = _BlockedAuthorizer();
  const ids = _Ids();

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('every financial mutation boundary blocks before persistence', () async {
    final operations = <Future<Object?> Function()>[
      () => LocalSaleService(db, ids, authorizer: blocked).createSale(
        const SaleDraft(
          shopId: 'shop',
          cashierId: 'actor',
          deviceId: 'device',
          lines: [],
          payments: [],
        ),
      ),
      () => LocalSaleReturnService(db, ids, authorizer: blocked).create(
        const SaleReturnDraft(
          shopId: 'shop',
          originalSaleId: 'sale',
          ownerId: 'actor',
          deviceId: 'device',
          refundMethod: PaymentMethod.cash,
          reason: 'reason',
          lines: [],
        ),
      ),
      () => LocalSaleVoidService(db, ids, authorizer: blocked).voidSale(
        shopId: 'shop',
        saleId: 'sale',
        ownerId: 'actor',
        deviceId: 'device',
        reason: 'reason',
      ),
      () => LocalCustomerPaymentService(db, ids, authorizer: blocked).receive(
        shopId: 'shop',
        customerId: 'customer',
        actorId: 'actor',
        deviceId: 'device',
        amountMinor: 1,
        method: PaymentMethod.cash,
      ),
      () => LocalPurchaseService(db, ids, authorizer: blocked).create(
        const PurchaseDraft(
          shopId: 'shop',
          supplierId: 'supplier',
          deviceId: 'device',
          ownerId: 'actor',
          lines: [],
          payments: [],
        ),
      ),
      () => LocalSupplierPaymentService(db, ids, authorizer: blocked).record(
        shopId: 'shop',
        supplierId: 'supplier',
        ownerId: 'actor',
        deviceId: 'device',
        amountMinor: 1,
        method: PaymentMethod.cash,
      ),
      () => LocalExpenseService(db, ids, authorizer: blocked).create(
        ExpenseDraft(
          shopId: 'shop',
          categoryId: 'category',
          categoryName: 'Other',
          amountMinor: 1,
          paymentMethod: PaymentMethod.cash,
          description: 'expense',
          ownerId: 'actor',
          deviceId: 'device',
          expenseAt: DateTime.utc(2026),
        ),
      ),
      () =>
          LocalInventoryAdjustmentService(db, ids, authorizer: blocked).record(
            shopId: 'shop',
            productId: 'product',
            ownerId: 'actor',
            deviceId: 'device',
            type: InventoryMovementType.manualAdjustment,
            quantity: 1,
            note: 'count',
          ),
    ];

    for (final operation in operations) {
      await expectLater(
        operation(),
        throwsA(isA<SubscriptionMutationBlocked>()),
      );
    }

    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.saleReturns).get(), isEmpty);
    expect(await db.select(db.saleVoids).get(), isEmpty);
    expect(await db.select(db.salePayments).get(), isEmpty);
    expect(await db.select(db.customerLedgerEntries).get(), isEmpty);
    expect(await db.select(db.purchases).get(), isEmpty);
    expect(await db.select(db.purchasePayments).get(), isEmpty);
    expect(await db.select(db.supplierLedgerEntries).get(), isEmpty);
    expect(await db.select(db.expenses).get(), isEmpty);
    expect(await db.select(db.inventoryMovements).get(), isEmpty);
    expect(await db.select(db.auditLogs).get(), isEmpty);
    expect(await db.select(db.syncOperations).get(), isEmpty);
  });
}

final class _BlockedAuthorizer implements FinancialMutationAuthorizer {
  const _BlockedAuthorizer();
  @override
  Future<EntitlementEvaluation> authorize({
    required String shopId,
    required String deviceId,
  }) => throw const SubscriptionMutationBlocked('Subscription expired.');
}

final class _Ids implements IdGenerator {
  const _Ids();
  @override
  String next() => throw StateError('IDs must not be allocated when blocked.');
}
