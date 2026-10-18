// Sale-screen keyboard behaviour on touch tablets: the search field never
// takes focus by itself, so the soft keyboard opens only when the cashier
// taps it; Search/Done, products, categories, checkout and returning from
// another tab all leave it closed; a hardware barcode scanner still works.
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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _surf = PosProduct(
  id: 'surf', name: 'Surf', salePriceMinor: 35000, stockQuantity: 9000,
  stockTrackingEnabled: true, barcode: '8964000000017', categoryId: 'household');
const _tea = PosProduct(
  id: 'tea', name: 'Tea', salePriceMinor: 29000, stockQuantity: 9000,
  stockTrackingEnabled: true, barcode: '8964000000024', categoryId: 'grocery');

final _searchField = find.byKey(const ValueKey('pos-search-field'));
final _bill = find.byKey(const ValueKey('current-bill-panel'));

Future<AppDatabase> _pumpPos(WidgetTester tester) async {
  // The Galaxy Tab A9+ landscape size.
  tester.view.physicalSize = const Size(1340, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  await tester.pumpWidget(MaterialApp(
    home: PosWorkspace(
      shopName: 'ALI Shop',
      cashierName: 'ahmed1',
      initialCatalog: const PosCatalogSnapshot(
        products: [_surf, _tea],
        categories: [PosCategory(id: 'household', name: 'Household'), PosCategory(id: 'grocery', name: 'Grocery')],
        customers: [],
      ),
      committer: _Committer(),
      salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
      offline: false,
      initialHasPendingSync: false,
      onLogout: () async {},
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return db;
}

Future<void> _disposePos(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(db.close);
}

bool _searchFocused(WidgetTester tester) =>
    tester.widget<EditableText>(find.descendant(of: _searchField, matching: find.byType(EditableText))).focusNode.hasFocus;

String _searchText(WidgetTester tester) => tester.widget<TextField>(_searchField).controller!.text;

/// The soft keyboard is shown exactly while a text input connection is open.
bool _keyboardShown(WidgetTester tester) => tester.testTextInput.isVisible;

Future<void> _openKeyboard(WidgetTester tester) async {
  await tester.tap(_searchField);
  await tester.pump();
  expect((_searchFocused(tester), _keyboardShown(tester)), (true, true), reason: 'an explicit tap opens it');
}

Finder _addOn(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(PosProductCard)), matching: find.text('Add'));

void main() {
  testWidgets('the Sale screen opens with the search unfocused and no keyboard', (tester) async {
    final db = await _pumpPos(tester);
    // Root cause guard: the search field must never request focus by itself.
    final search = find.widgetWithText(TextField, 'Search product or scan barcode');
    expect(tester.widget<TextField>(search).autofocus, isFalse);
    expect(tester.widget<EditableText>(find.descendant(of: search, matching: find.byType(EditableText))).focusNode.hasFocus,
        isFalse);
    expect(_keyboardShown(tester), isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'pos-hardware-scan',
        reason: 'the Sale screen, not a text field, holds focus');
    await _disposePos(tester, db);
  });

  testWidgets('only an explicit tap opens the keyboard; typing still searches', (tester) async {
    final db = await _pumpPos(tester);
    await _openKeyboard(tester);
    await tester.enterText(_searchField, 'Surf');
    await tester.pump();
    expect(find.byType(PosProductCard), findsOneWidget);
    expect(_searchText(tester), 'Surf');
    await _disposePos(tester, db);
  });

  testWidgets('Search / Done on the keyboard closes it and keeps the search', (tester) async {
    final db = await _pumpPos(tester);
    await _openKeyboard(tester);
    await tester.enterText(_searchField, 'Tea');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect((_searchFocused(tester), _keyboardShown(tester)), (false, false));
    expect(find.byType(PosProductCard), findsOneWidget, reason: 'the filter stays');
    await _disposePos(tester, db);
  });

  testWidgets('returning to Sale from another tab does not reopen the keyboard', (tester) async {
    final db = await _pumpPos(tester);
    await _openKeyboard(tester);
    await tester.tap(find.text('Bills'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_keyboardShown(tester), isFalse, reason: 'leaving Sale closes it');
    await tester.tap(find.text('Sale'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_searchFocused(tester), isFalse);
    expect(_keyboardShown(tester), isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'pos-hardware-scan');
    await _disposePos(tester, db);
  });

  testWidgets('tapping a product or a category closes the keyboard and does not reopen it', (tester) async {
    final db = await _pumpPos(tester);
    await _openKeyboard(tester);
    await tester.tap(_addOn('Surf'));
    await tester.pump();
    expect((_searchFocused(tester), _keyboardShown(tester)), (false, false));
    expect(find.descendant(of: _bill, matching: find.text('Surf')), findsOneWidget);

    await _openKeyboard(tester);
    await tester.tap(find.text('Grocery'));
    await tester.pump();
    expect((_searchFocused(tester), _keyboardShown(tester)), (false, false));
    await tester.tap(_addOn('Tea'));
    await tester.pump();
    expect(_keyboardShown(tester), isFalse);
    await _disposePos(tester, db);
  });

  testWidgets('opening and closing checkout does not bring the keyboard back', (tester) async {
    final db = await _pumpPos(tester);
    await tester.tap(_addOn('Surf'));
    await tester.pump();
    await _openKeyboard(tester);
    await tester.tap(find.byKey(const ValueKey('pay-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentDialog), findsOneWidget);
    expect(_keyboardShown(tester), isFalse, reason: 'checkout released the search field');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((_searchFocused(tester), _keyboardShown(tester)), (false, false),
        reason: 'closing the dialog must not hand focus back to the search field');
    await _disposePos(tester, db);
  });

  testWidgets('a hardware barcode scanner still adds the exact product without the soft keyboard', (tester) async {
    final db = await _pumpPos(tester);
    for (final digit in '8964000000024'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(0x30 + int.parse(digit)), character: digit);
    }
    await tester.pump();
    expect(_searchText(tester), '8964000000024', reason: 'scanner keys reach the search');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.descendant(of: _bill, matching: find.text('Tea')), findsOneWidget);
    expect(_searchText(tester), isEmpty, reason: 'cleared after a match, as before');
    expect(_keyboardShown(tester), isFalse, reason: 'scanning never opens the soft keyboard');
    // Backspace edits a mistyped hardware entry; Enter on an empty search does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_searchText(tester), isEmpty);
    await _disposePos(tester, db);
  });

  testWidgets('a scanner after the cashier used the keyboard still works; no double typing', (tester) async {
    final db = await _pumpPos(tester);
    await _openKeyboard(tester);
    await tester.enterText(_searchField, 'Su');
    // Hardware key events while the field is focused are the field's own:
    // the Sale-screen handler must not insert them a second time.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR, character: 'r');
    await tester.pump();
    expect(_searchText(tester), 'Su');
    // Barcode typed into the field and submitted with the keyboard action.
    await tester.enterText(_searchField, '8964000000017');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.descendant(of: _bill, matching: find.text('Surf')), findsOneWidget);
    expect((_searchFocused(tester), _keyboardShown(tester)), (false, false));
    // The next scan arrives through the Sale screen.
    for (final digit in '8964000000024'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey(0x30 + int.parse(digit)), character: digit);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.descendant(of: _bill, matching: find.text('Tea')), findsOneWidget);
    await _disposePos(tester, db);
  });
}

final class _Committer implements PosSaleCommitter {
  @override
  Future<CreatedSale> complete(String checkoutId, PosCart cart, PosPaymentPlan payment) => throw UnimplementedError();
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
