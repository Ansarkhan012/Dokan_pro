import 'package:drift/native.dart';
import 'package:dukaan_pro/app/owner_access.dart';
import 'package:dukaan_pro/auth/owner_mode_lock.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/bill_reference.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sale id observed on the pilot tablet's Bills screen.
const pilotSaleId = '01a0f730-252b-7437-a3b3-e5a10509f516';

void main() {
  group('owner mode lock', () {
    test('cashier mode lock survives an app restart', () async {
      final store = _MemoryLockStore();
      final lock = OwnerModeLock(store);
      await lock.load();
      expect(lock.ownerAccessAllowed, isTrue);
      await lock.engage();
      expect(lock.ownerAccessAllowed, isFalse);

      final restarted = OwnerModeLock(store);
      expect(restarted.ownerAccessAllowed, isFalse, reason: 'before load');
      await restarted.load();
      expect(restarted.ownerAccessAllowed, isFalse);
      await restarted.release();
      expect(restarted.ownerAccessAllowed, isTrue);
      expect(store.locked, isFalse);
    });

    test('unreadable lock fails closed; unsaved lock is reported', () async {
      final unreadable = OwnerModeLock(_MemoryLockStore(failRead: true));
      await unreadable.load();
      expect(unreadable.ownerAccessAllowed, isFalse);

      final unsaved = OwnerModeLock(_MemoryLockStore(failWrite: true));
      await unsaved.load();
      await expectLater(unsaved.engage(), throwsA(isA<StateError>()));
      expect(unsaved.ownerAccessAllowed, isFalse);
    });
  });

  group('owner-only screens', () {
    testWidgets('cashier mode hides the Owner Dashboard and owner actions', (
      tester,
    ) async {
      final lock = await _lock(locked: true);
      await tester.pumpWidget(_hub(lock, _Reauth('owner-pass')));

      expect(find.text('Owner Dashboard'), findsNothing);
      expect(find.text('Expenses'), findsNothing);
      expect(find.text('Unlock owner mode'), findsOneWidget);
      expect(find.text('NET PROFIT'), findsNothing);
    });

    testWidgets('direct navigation to an owner route is rejected', (
      tester,
    ) async {
      final lock = await _lock(locked: true);
      await tester.pumpWidget(_hub(lock, _Reauth('owner-pass')));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(ownerOnlyRoute(lock, (_) => const _FakeDashboard()));
      await tester.pumpAndSettle();

      expect(find.text('Owner access required'), findsOneWidget);
      expect(find.byType(_FakeDashboard), findsNothing);
      expect(find.text('NET PROFIT'), findsNothing);
    });

    testWidgets('wrong password keeps owner mode locked', (tester) async {
      final lock = await _lock(locked: true);
      await tester.pumpWidget(_hub(lock, _Reauth('owner-pass')));

      await tester.enterText(
        find.byKey(const ValueKey('owner-unlock-password')),
        'cashier-guess',
      );
      await tester.tap(find.text('Unlock owner mode'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong owner password.'), findsOneWidget);
      expect(find.text('Owner Dashboard'), findsNothing);
      expect(lock.ownerAccessAllowed, isFalse);
    });

    testWidgets('owner password unlocks owner mode and the dashboard opens', (
      tester,
    ) async {
      final lock = await _lock(locked: true);
      await tester.pumpWidget(_hub(lock, _Reauth('owner-pass')));

      await tester.enterText(
        find.byKey(const ValueKey('owner-unlock-password')),
        'owner-pass',
      );
      await tester.tap(find.text('Unlock owner mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Owner Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('NET PROFIT'), findsOneWidget);
    });

    testWidgets('owner mode opens owner screens; locking closes them', (
      tester,
    ) async {
      final lock = await _lock(locked: false);
      await tester.pumpWidget(_hub(lock, _Reauth('owner-pass')));

      expect(find.text('Unlock owner mode'), findsNothing);
      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();
      expect(find.text('EXPENSES SCREEN'), findsOneWidget);

      await lock.engage();
      await tester.pump();
      expect(find.text('EXPENSES SCREEN'), findsNothing);
      expect(find.text('Owner access required'), findsOneWidget);
    });
  });

  group('bill reference', () {
    test('formats the UUID tail and prefers a stored invoice number', () {
      expect(billReference(pilotSaleId), 'Bill #0509F516');
      expect(
        billReference(pilotSaleId, invoiceNumber: ' 000001 '),
        'Bill #000001',
      );
      expect(searchedBillCode('Bill #0509F516'), '0509f516');
      expect(searchedBillCode('#0509f516'), '0509f516');
      expect(searchedBillCode('Ahmed'), isNull);
    });

    test(
      'cashier sale keeps its UUID while Bills shows the bill reference',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final now = DateTime.now().toUtc();
        await _seedShop(db, now);

        final sale =
            await LocalSaleService(
              db,
              const UuidV7Generator(),
              clock: () => now,
            ).createSale(
              const SaleDraft(
                saleId: pilotSaleId,
                shopId: 'shop',
                cashierId: 'cashier',
                deviceId: 'device',
                lines: [SaleLineDraft(productId: 'product', quantity: 1000)],
                payments: [
                  SalePaymentDraft(
                    method: PaymentMethod.cash,
                    amountMinor: 20000,
                  ),
                ],
              ),
            );

        expect(sale.saleId, pilotSaleId);
        expect((await db.select(db.sales).getSingle()).id, pilotSaleId);
        expect(
          (await db.select(db.syncOperations).getSingle()).entityId,
          pilotSaleId,
        );

        final repo = DriftSalesHistoryRepository(db, shopId: 'shop');
        final range = ReportRange(
          now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 1)),
          label: 'test',
        );
        final row = (await repo.page(
          filter: SaleHistoryFilter(range: range),
        )).single;
        expect(row.id, pilotSaleId);
        expect(row.reference, 'Bill #0509F516');
        expect(row.reference, isNot(contains(pilotSaleId)));

        final receipt = await repo.receipt(await repo.detail(row));
        expect(receipt.reference, 'Bill #0509F516');

        final searched = await repo.page(
          filter: SaleHistoryFilter(range: range, query: 'Bill #0509F516'),
        );
        expect(searched.single.id, pilotSaleId);
        expect((await repo.sale(pilotSaleId))?.reference, 'Bill #0509F516');
      },
    );
  });
}

Future<OwnerModeLock> _lock({required bool locked}) async {
  final lock = OwnerModeLock(_MemoryLockStore(locked: locked));
  await lock.load();
  return lock;
}

Widget _hub(OwnerModeLock lock, OwnerReauthenticator reauthenticator) =>
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            OwnerModeSection(
              lock: lock,
              reauthenticator: reauthenticator,
              actions: [
                OwnerAction(
                  label: 'Owner Dashboard',
                  icon: Icons.analytics_outlined,
                  primary: true,
                  builder: (_) => const _FakeDashboard(),
                ),
                OwnerAction(
                  label: 'Expenses',
                  icon: Icons.payments_outlined,
                  builder: (_) => const Scaffold(body: Text('EXPENSES SCREEN')),
                ),
              ],
            ),
          ],
        ),
      ),
    );

class _FakeDashboard extends StatelessWidget {
  const _FakeDashboard();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('NET PROFIT'));
}

final class _Reauth implements OwnerReauthenticator {
  _Reauth(this.password);
  final String password;
  @override
  Future<bool> verifyPassword(String value) async => value == password;
}

final class _MemoryLockStore implements OwnerModeLockStore {
  _MemoryLockStore({
    this.locked = false,
    this.failRead = false,
    this.failWrite = false,
  });
  bool locked;
  final bool failRead, failWrite;
  @override
  Future<bool> read() async {
    if (failRead) throw StateError('storage unavailable');
    return locked;
  }

  @override
  Future<void> write(bool value) async {
    if (failWrite) throw StateError('storage unavailable');
    locked = value;
  }
}

Future<void> _seedShop(AppDatabase db, DateTime now) async {
  final t = now.millisecondsSinceEpoch ~/ 1000;
  for (final sql in [
    "insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at) values('shop','Test','','','trial','trial',$t,$t)",
    "insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at) values('device','shop','Tablet','androidTablet','x',$t,$t)",
    "insert into cashiers(id,shop_id,display_name,login_code,created_at,updated_at) values('cashier','shop','Ali','1',$t,$t)",
    "insert into shop_products(id,shop_id,custom_name,purchase_price,sale_price,created_at,updated_at) values('product','shop','Daal',15000,20000,$t,$t)",
  ]) {
    await db.customStatement(sql);
  }
}
