// The cashier is told at once, in English or Urdu, when a product cannot be
// sold: no stock, not enough stock for another unit, or stock already below
// zero. Checkout refuses the same sales inside its transaction (see
// stage1_regressions_test.dart); this is the cart side.
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));

PosProduct _product(String id, String name, int stock) => PosProduct(
  id: id,
  name: name,
  salePriceMinor: 35000,
  stockQuantity: stock,
  stockTrackingEnabled: true,
  categoryId: 'household',
);

final _empty = _product('surf', 'Surf', 0);
final _two = _product('daal', 'Daal', 2000);
final _negative = _product('oil', 'Oil', -3000);

void main() {
  for (final urdu in [false, true]) {
    final l10n = urdu ? _ur : _en;
    final lang = urdu ? 'Urdu' : 'English';

    testWidgets('$lang: a product with no stock is not added', (tester) async {
      await _pump(tester, urdu: urdu);
      await tester.tap(find.textContaining('Surf').first);
      await tester.pump();
      expect(
        find.text(
          l10n.saleErrNotEnoughStock(_name(urdu, 'Surf'), _qty(urdu, '0')),
        ),
        findsOneWidget,
      );
      _expectPayDisabled(tester);
      await _dispose(tester);
    });

    testWidgets('$lang: stock below zero is explained and blocks the sale', (
      tester,
    ) async {
      await _pump(tester, urdu: urdu);
      await tester.tap(find.textContaining('Oil').first);
      await tester.pump();
      expect(
        find.text(
          l10n.saleErrStockBelowZero(_name(urdu, 'Oil'), _qty(urdu, '-3')),
        ),
        findsOneWidget,
      );
      _expectPayDisabled(tester);
      await _dispose(tester);
    });

    testWidgets('$lang: exactly the stock can be added, one more cannot', (
      tester,
    ) async {
      await _pump(tester, urdu: urdu);
      final daal = find.textContaining('Daal').first;
      await tester.tap(daal);
      await tester.pump();
      await tester.tap(daal);
      await tester.pump();
      expect(
        find.text(
          l10n.saleErrNotEnoughStock(_name(urdu, 'Daal'), _qty(urdu, '2')),
        ),
        findsNothing,
      );
      // A third tap (and the bill's + button) would oversell.
      await tester.tap(daal);
      await tester.pump();
      expect(
        find.text(
          l10n.saleErrNotEnoughStock(_name(urdu, 'Daal'), _qty(urdu, '2')),
        ),
        findsOneWidget,
      );
      final plus = find.widgetWithIcon(OutlinedButton, Icons.add);
      if (plus.evaluate().isNotEmpty) {
        await tester.tap(plus.first);
        await tester.pump();
      }
      final pay = tester.widget<FilledButton>(
        find.byKey(const ValueKey('pay-button')),
      );
      expect(pay.onPressed, isNotNull);
      // Still 2 x Rs 350.
      expect(find.textContaining('700.00'), findsWidgets);
      expect(find.textContaining('1050.00'), findsNothing);
      await _dispose(tester);
    });
  }
}

String _name(bool urdu, String name) => urdu ? isolateAuto(name) : name;
String _qty(bool urdu, String q) => urdu ? isolateLtr(q) : q;

void _expectPayDisabled(WidgetTester tester) {
  final pay = find.byKey(const ValueKey('pay-button'));
  if (pay.evaluate().isEmpty) return;
  expect(tester.widget<FilledButton>(pay).onPressed, isNull);
}

AppDatabase? _db;

Future<void> _pump(WidgetTester tester, {required bool urdu}) async {
  tester.view.physicalSize = const Size(1340, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = _db = AppDatabase(NativeDatabase.memory());
  await tester.pumpWidget(
    LocalizedMaterialApp(
      controller: LocaleController(
        initialLocale: urdu ? LocaleController.urdu : LocaleController.english,
      ),
      home: PosWorkspace(
        shopName: 'Ali Shop',
        cashierName: 'Ahmed',
        initialCatalog: PosCatalogSnapshot(
          products: [_empty, _two, _negative],
          categories: const [PosCategory(id: 'household', name: 'Household')],
          customers: const [],
          allowNegativeStock: false,
        ),
        committer: _Committer(),
        salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
        offline: false,
        initialHasPendingSync: false,
        onLogout: () async {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(_db!.close);
}

final class _Committer implements PosSaleCommitter {
  @override
  Future<CreatedSale> complete(
    String checkoutId,
    PosCart cart,
    PosPaymentPlan payment,
  ) => throw UnimplementedError();
  @override
  Future<PosCatalogSnapshot> reloadCatalog() => throw UnimplementedError();
  @override
  Future<bool> triggerSync() async => false;
  @override
  Stream<SyncHealth> watchSyncHealth() => Stream.value(SyncHealth.synced);
  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {}
  @override
  Future<List<CustomerAccount>> searchCustomers(String query) async => [];
  @override
  Future<List<CustomerLedgerLine>> statement(String id) async => [];
}
