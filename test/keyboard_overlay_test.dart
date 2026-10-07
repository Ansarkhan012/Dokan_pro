import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
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

/// Android navigation bar height reported as bottom view padding.
const _navBar = 48.0;

/// The soft keyboard overlays the tablet shell (like the ChatGPT tablet app):
/// opening it must not move or resize anything in the POS layout.
void main() {
  for (final (size, keyboard) in const [
    (Size(1280, 800), 330.0),
    (Size(1280, 800), 420.0),
    (Size(1340, 800), 380.0),
    (Size(1366, 768), 400.0),
    (Size(1024, 600), 340.0),
    (Size(1920, 1080), 480.0),
  ]) {
    final name =
        '${size.width.toInt()}x${size.height.toInt()} keyboard $keyboard';
    testWidgets('New Sale geometry is unchanged by the keyboard: $name', (
      tester,
    ) async {
      final db = await _pumpPos(tester, size);
      // Add a line so Pay is enabled and the bill has content.
      await tester.tap(find.text('Add').first);
      await tester.pump();
      final before = _rects(tester);

      // Tap search and open the keyboard the way Android reports it: bottom
      // insets grow, the visible padding drops, the view padding is kept.
      await tester.tap(find.byType(TextField).first);
      _openKeyboard(tester, keyboard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(_rects(tester), before, reason: 'keyboard open');

      await tester.enterText(find.byType(TextField).first, 'Product 1');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      expect(_rects(tester), before, reason: 'typing in search');

      _closeKeyboard(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(_rects(tester), before, reason: 'keyboard closed');

      // Pay still opens the payment dialog.
      await tester.tap(find.byKey(const ValueKey('pay-button')));
      await tester.pumpAndSettle();
      expect(find.text('Complete Sale'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposePos(tester, db);
    });
  }

  testWidgets('payment dialog over the keyboard leaves the POS untouched', (
    tester,
  ) async {
    final db = await _pumpPos(tester, const Size(1280, 800));
    await tester.tap(find.text('Add').first);
    await tester.pump();
    final before = _rects(tester);
    await tester.tap(find.byKey(const ValueKey('pay-button')));
    await tester.pumpAndSettle();
    _openKeyboard(tester, 420);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_rects(tester), before);
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Complete Sale'));
    await tester.pumpAndSettle();
    expect(find.text('Complete Sale').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposePos(tester, db);
  });

  testWidgets('a genuinely small window still adapts without overflow', (
    tester,
  ) async {
    final db = await _pumpPos(tester, const Size(1024, 380), navBar: 0);
    expect(tester.takeException(), isNull);
    // Short window: the heading gives its height to the product grid.
    expect(find.text('New Sale'), findsNothing);
    expect(find.byKey(const ValueKey('pay-button')), findsOneWidget);
    await _disposePos(tester, db);
  });
}

Map<String, Rect> _rects(WidgetTester tester) => {
  'header': tester.getRect(find.byKey(const ValueKey('pos-top-bar'))),
  'sidebar': tester.getRect(find.byKey(const ValueKey('cashier-sidebar'))),
  'heading': tester.getRect(find.text('New Sale')),
  'search': tester.getRect(find.byType(TextField).first),
  'first product': tester.getRect(find.byType(PosProductCard).first),
  'current bill': tester.getRect(
    find.byKey(const ValueKey('current-bill-panel')),
  ),
  'pay': tester.getRect(find.byKey(const ValueKey('pay-button'))),
};

void _openKeyboard(WidgetTester tester, double keyboard) {
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = FakeViewPadding.zero;
}

void _closeKeyboard(WidgetTester tester) {
  tester.view.resetViewInsets();
  tester.view.padding = const FakeViewPadding(bottom: _navBar);
}

Future<AppDatabase> _pumpPos(
  WidgetTester tester,
  Size size, {
  double navBar = _navBar,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: navBar);
  tester.view.viewPadding = FakeViewPadding(bottom: navBar);
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xff176b52)),
      home: PosWorkspace(
        shopName: 'ALI Shop',
        cashierName: 'ahmed1',
        initialCatalog: PosCatalogSnapshot(
          products: [
            for (var i = 0; i < 8; i++)
              PosProduct(
                id: 'p$i',
                name: 'Product $i',
                salePriceMinor: 57000,
                stockQuantity: 9000,
                stockTrackingEnabled: true,
                lowStockLevel: 2000,
                categoryId: 'grocery',
              ),
          ],
          categories: const [PosCategory(id: 'grocery', name: 'Grocery')],
          customers: const [],
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
  return db;
}

Future<void> _disposePos(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(db.close);
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
  Stream<SyncHealth> watchSyncHealth() => const Stream.empty();
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
