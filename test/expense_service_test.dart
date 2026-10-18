import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/expenses/drift_expense_repository.dart';
import 'package:dukaan_pro/features/expenses/expense_models.dart';
import 'package:dukaan_pro/features/expenses/local_expense_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late _Ids ids;
  // DriftExpenseRepository totals "this month" from the real clock, so the
  // fixture date is day 14 of the month captured when the suite starts (a
  // fixed 2026-09-14 stopped being "this month" on 2026-10-01).
  final month = DateTime.now();
  final now = DateTime(month.year, month.month, 14, 12);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ids = _Ids();
    await seed(db, now);
  });
  tearDown(() => db.close());
  test('creates expense, audit and queue atomically', () async {
    final made = await create(
      db,
      ids,
      now,
      'electricity',
      'Electricity',
      1250000,
      'September electricity bill',
      PaymentMethod.digital,
    );
    expect(made.expenseId, isNotEmpty);
    expect(await db.select(db.expenses).get(), hasLength(1));
    expect(await db.select(db.auditLogs).get(), hasLength(1));
    final op = await db.select(db.syncOperations).getSingle();
    expect(jsonDecode(op.payload)['operation'], 'sync_expense');
  });
  test('validates amount, method, category and description', () async {
    await expectLater(
      create(
        db,
        ids,
        now,
        'electricity',
        'Electricity',
        0,
        'Bill',
        PaymentMethod.cash,
      ),
      throwsArgumentError,
    );
    await expectLater(
      create(
        db,
        ids,
        now,
        'electricity',
        'Electricity',
        100,
        '',
        PaymentMethod.cash,
      ),
      throwsArgumentError,
    );
    await expectLater(
      create(
        db,
        ids,
        now,
        'missing',
        'Missing',
        100,
        'Bill',
        PaymentMethod.cash,
      ),
      throwsStateError,
    );
    expect(await db.select(db.expenses).get(), isEmpty);
  });
  test('category/date filters and exact monthly totals', () async {
    await create(
      db,
      ids,
      now,
      'electricity',
      'Electricity',
      1250000,
      'Electric bill',
      PaymentMethod.digital,
    );
    await create(
      db,
      ids,
      now,
      'rent',
      'Rent',
      2500000,
      'Rent',
      PaymentMethod.cash,
    );
    await create(
      db,
      ids,
      now,
      'transport',
      'Transport',
      120000,
      'Delivery transport',
      PaymentMethod.cash,
    );
    final repo = DriftExpenseRepository(db, shopId: 'shop');
    expect((await repo.query()).monthMinor, 3870000);
    expect(
      (await repo.query(categoryId: 'rent')).rows.single.amountMinor,
      2500000,
    );
    expect(
      (await repo.query(search: 'delivery')).rows.single.category,
      'Transport',
    );
    expect(
      (await repo.query(from: DateTime(now.year, now.month, 15))).rows,
      isEmpty,
    );
  });
  test('expense persists after database restart', () async {
    await db.close();
    final dir = await Directory.systemTemp.createTemp('dukaan-expense-');
    final file = File('${dir.path}${Platform.pathSeparator}db.sqlite');
    var persisted = AppDatabase(NativeDatabase(file));
    await seed(persisted, now);
    await create(
      persisted,
      _Ids(),
      now,
      'rent',
      'Rent',
      2500000,
      'Rent',
      PaymentMethod.cash,
    );
    await persisted.close();
    persisted = AppDatabase(NativeDatabase(file));
    expect(await persisted.select(persisted.expenses).get(), hasLength(1));
    expect(
      await persisted.select(persisted.syncOperations).get(),
      hasLength(1),
    );
    await persisted.close();
    await dir.delete(recursive: true);
    db = AppDatabase(NativeDatabase.memory());
  });
}

Future<void> seed(AppDatabase db, DateTime now) async {
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
  for (final c in [
    ('electricity', 'Electricity'),
    ('rent', 'Rent'),
    ('transport', 'Transport'),
  ]) {
    await db
        .into(db.expenseCategories)
        .insert(
          ExpenseCategoriesCompanion.insert(
            id: c.$1,
            shopId: 'shop',
            name: c.$2,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

Future<CreatedExpense> create(
  AppDatabase db,
  IdGenerator ids,
  DateTime now,
  String categoryId,
  String category,
  int amount,
  String description,
  PaymentMethod method,
) => LocalExpenseService(db, ids, clock: () => now).create(
  ExpenseDraft(
    shopId: 'shop',
    categoryId: categoryId,
    categoryName: category,
    amountMinor: amount,
    paymentMethod: method,
    description: description,
    ownerId: 'owner',
    deviceId: 'device',
    expenseAt: now,
  ),
);

final class _Ids implements IdGenerator {
  int n = 0;
  @override
  String next() =>
      '00000000-0000-7000-8000-${(++n).toString().padLeft(12, '0')}';
}
