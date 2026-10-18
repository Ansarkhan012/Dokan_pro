import 'dart:async';

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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tablet sizes and on-screen keyboard heights seen on supported devices,
/// including the Samsung tablet where the 36 px sidebar overflow appeared.
const _keyboardCases = [
  (Size(1280, 800), 0.0),
  (Size(1280, 800), 330.0),
  (Size(1280, 800), 420.0),
  (Size(1340, 800), 380.0),
  (Size(1366, 768), 400.0),
  (Size(1024, 600), 280.0),
  (Size(1024, 600), 340.0),
  (Size(1920, 1080), 480.0),
  (Size(800, 1280), 420.0),
];

void main() {
  for (final (size, keyboard) in _keyboardCases) {
    final name =
        '${size.width.toInt()}x${size.height.toInt()} keyboard $keyboard';
    testWidgets('New Sale has no overflow: $name', (tester) async {
      final db = await _pumpPos(tester, size, keyboard: keyboard);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('cashier-sidebar')), findsOneWidget);
      // Every destination stays reachable.
      for (final label in ['Sale', 'Products', 'Bills', 'Khata']) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('cashier-sidebar')),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      // U1: the non-functional Inventory placeholder is gone for cashiers;
      // owner Inventory stays in the owner actions.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cashier-sidebar')),
          matching: find.text('Inventory'),
        ),
        findsNothing,
      );
      if (find.byKey(const ValueKey('open-cart-button')).evaluate().isEmpty) {
        // Wide layout: Current Bill and Pay stay usable beside the catalog.
        await tester.tap(find.text('Add').first);
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('pay-button')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('pay-button')).hitTestable(),
          findsOneWidget,
        );
      } else {
        // Narrow layout: the bill opens as a sheet with Pay reachable.
        await tester.tap(find.text('Add').first);
        await tester.tap(find.byKey(const ValueKey('open-cart-button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('pay-button')));
        expect(find.byKey(const ValueKey('pay-button')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await _disposePos(tester, db);
    });

    testWidgets('Bills has no overflow: $name', (tester) async {
      final db = await _pumpPos(tester, size, keyboard: keyboard);
      await tester.tap(find.text('Bills'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Today'), findsWidgets);
      await _disposePos(tester, db);
    });
  }

  testWidgets('sidebar labels stay on one line', (tester) async {
    final db = await _pumpPos(tester, const Size(1280, 800));
    for (final label in ['Products', 'Khata']) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const ValueKey('cashier-sidebar')),
          matching: find.text(label),
        ),
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      expect(paragraph.size.height, lessThan(20), reason: '$label wrapped');
    }
    await _disposePos(tester, db);
  });

  testWidgets('payment modal stays fully reachable with the keyboard open', (
    tester,
  ) async {
    for (final (size, keyboard) in const [
      (Size(1280, 800), 420.0),
      (Size(1024, 600), 340.0),
      (Size(1280, 400), 200.0),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      PosPaymentPlan? plan;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => plan = await showDialog<PosPaymentPlan>(
                  context: context,
                  builder: (_) =>
                      const PaymentDialog(totalMinor: 57000, customers: []),
                ),
                child: const Text('pay'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pay'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.pumpAndSettle();
      expect(find.text('Change: Rs 430.00'), findsOneWidget);
      await tester.ensureVisible(find.text('Complete Sale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete Sale'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(plan!.cashReceivedMinor, 100000);
      expect(plan!.payments.single.amountMinor, 57000);
    }
  });
}

Future<AppDatabase> _pumpPos(
  WidgetTester tester,
  Size size, {
  double keyboard = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
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
