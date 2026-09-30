import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/drift_customer_repository.dart';
import 'package:dukaan_pro/features/customers/local_customer_payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 9, 13, 12);
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
            createdAt: now,
            updatedAt: now,
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
            deviceIdentifier: 'device-uuid',
            createdAt: now,
          ),
        );
    await db
        .into(db.cashiers)
        .insert(
          CashiersCompanion.insert(
            id: 'cashier-a',
            shopId: 'shop-a',
            displayName: 'Ali',
            loginCode: 'ali',
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
            name: 'Ahmed Khan',
            phone: const Value('03001234567'),
            creditLimit: const Value(500000),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.customerLedgerEntries)
        .insert(
          CustomerLedgerEntriesCompanion.insert(
            id: 'debt-a',
            shopId: 'shop-a',
            customerId: 'customer-a',
            type: CustomerLedgerType.creditSale,
            amount: 300000,
            createdBy: 'cashier-a',
            createdAt: now,
          ),
        );
  });
  tearDown(() => db.close());

  test('search and balance derive from append-only ledger', () async {
    final repository = DriftCustomerRepository(db, shopId: 'shop-a');
    expect((await repository.search('0300')).single.balanceMinor, 300000);
    expect(await repository.search('missing'), isEmpty);
  });

  test(
    'receive payment is atomic, negative by type, audited and queued',
    () async {
      await LocalCustomerPaymentService(
        db,
        _Ids(),
        clock: () => now.add(const Duration(hours: 1)),
      ).receive(
        shopId: 'shop-a',
        customerId: 'customer-a',
        actorId: 'cashier-a',
        deviceId: 'device-a',
        amountMinor: 100000,
        method: PaymentMethod.cash,
      );
      final account = (await DriftCustomerRepository(
        db,
        shopId: 'shop-a',
      ).search('Ahmed')).single;
      expect(account.balanceMinor, 200000);
      final payment = (await db.select(db.customerLedgerEntries).get())
          .singleWhere((e) => e.type == CustomerLedgerType.paymentReceived);
      expect(
        payment.amount,
        100000,
      ); // Stored as a positive magnitude; the type supplies the negative sign.
      expect(payment.paymentMethod, 'cash');
      expect(await db.select(db.auditLogs).get(), hasLength(1));
      final operation = await db.select(db.syncOperations).getSingle();
      expect(
        jsonDecode(operation.payload)['operation'],
        'sync_customer_payment',
      );
    },
  );

  test('invalid payment rolls back all financial writes', () async {
    await expectLater(
      LocalCustomerPaymentService(db, _Ids()).receive(
        shopId: 'shop-a',
        customerId: 'customer-a',
        actorId: 'cashier-a',
        deviceId: 'device-a',
        amountMinor: 0,
        method: PaymentMethod.cash,
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.auditLogs).get(), isEmpty);
    expect(await db.select(db.syncOperations).get(), isEmpty);
  });
  test('payment cannot exceed current receivable', () async {
    await expectLater(
      LocalCustomerPaymentService(db, _Ids()).receive(
        shopId: 'shop-a',
        customerId: 'customer-a',
        actorId: 'cashier-a',
        deviceId: 'device-a',
        amountMinor: 300001,
        method: PaymentMethod.cash,
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.auditLogs).get(), isEmpty);
    expect(await db.select(db.syncOperations).get(), isEmpty);
  });
}

final class _Ids implements IdGenerator {
  int value = 0;
  @override
  String next() =>
      '00000000-0000-7000-8000-${(++value).toString().padLeft(12, '0')}';
}
