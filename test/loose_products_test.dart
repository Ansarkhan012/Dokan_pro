// U2 loose / measured products on the device: integer parsing and
// rounding, the picker's stock rules, the cart's single measured line, the
// POS add/edit flow (keyboard overlay included), owner create/edit dialogs,
// and the local catalog reading the owner's setup.
import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/format/measure_format.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/pos/measured_quantity_picker.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart' hide formatPkr;
import 'package:dukaan_pro/features/products/custom_product_dialog.dart';
import 'package:dukaan_pro/features/products/drift_product_management_repository.dart';
import 'package:dukaan_pro/features/products/edit_product_dialog.dart';
import 'package:dukaan_pro/features/products/product_management_gateway.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/products/product_management_service.dart';
import 'package:dukaan_pro/features/receipts/receipt_model.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:dukaan_pro/features/receipts/receipt_view.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _atta = PosProduct(
  id: 'atta',
  name: 'Atta',
  salePriceMinor: 13000, // Rs 130/kg
  stockQuantity: 40000, // 40 kg
  stockTrackingEnabled: true,
  measureUnit: MeasureUnit.kg,
  measurePresets: [250, 500, 1000, 2500, 10000, 20000, 40000],
);

const _oil = PosProduct(
  id: 'oil',
  name: 'Oil',
  salePriceMinor: 17500, // Rs 175/L
  stockQuantity: 20000,
  stockTrackingEnabled: true,
  measureUnit: MeasureUnit.liter,
);

const _surf = PosProduct(
  id: 'surf',
  name: 'Surf',
  salePriceMinor: 35000,
  stockQuantity: 9000,
  stockTrackingEnabled: true,
);

/// Reads what the picker returned after it closed.
int? _lastPick;

Future<void> _pumpPickerHost(
  WidgetTester tester,
  PosProduct product, {
  bool allowNegativeStock = true,
  int alreadyInCart = 0,
  int? editing,
  Size size = const Size(1280, 800),
  double keyboard = 0,
}) async {
  _lastPick = null;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          resizeToAvoidBottomInset: false,
          body: TextButton(
            onPressed: () async => _lastPick = await showMeasuredQuantityPicker(
              context,
              product: product,
              allowNegativeStock: allowNegativeStock,
              alreadyInCart: alreadyInCart,
              editing: editing,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('integer parsing, bounds and rounding', () {
    test('typed quantities become exact thousandths', () {
      for (final (text, grams, expected) in [
        ('250', true, 250),
        ('500', true, 500),
        ('1', false, 1000),
        ('2.5', false, 2500),
        ('10', false, 10000),
        ('20', false, 20000),
        ('40', false, 40000),
        ('0.25', false, 250),
        ('1.001', false, 1001),
        ('750', true, 750), // ml
        ('1.25', false, 1250), // L
      ]) {
        expect(parseMeasureInput(text, fractionUnit: grams), expected, reason: text);
      }
    });

    test('invalid, zero, negative and excess precision are rejected', () {
      for (final (text, grams) in [
        ('', false),
        ('abc', false),
        ('-1', false),
        ('-250', true),
        ('1.2345', false),
        ('2.5', true), // grams are whole
        ('1.', false),
        ('.5', false),
        ('1e3', false),
        ('1,5', false),
      ]) {
        expect(parseMeasureInput(text, fractionUnit: grams), isNull, reason: '"$text"');
      }
      expect(measureQuantityError(parseMeasureInput('0', fractionUnit: false)), isNotNull);
      expect(measureQuantityError(parseMeasureInput('0', fractionUnit: true)), isNotNull);
      expect(measureQuantityError(maxMeasureQuantity), isNull);
      expect(measureQuantityError(maxMeasureQuantity + 1), isNotNull, reason: 'safe upper bound');
      expect(measureQuantityError(parseMeasureInput('1001', fractionUnit: false)), isNotNull);
    });

    test('line totals are exact paisa', () {
      expect(lineTotalMinor(13000, 250), 3250); // Rs 32.50
      expect(lineTotalMinor(13000, 2500), 32500); // Rs 325.00
      expect(lineTotalMinor(17500, 333), 5828); // Rs 58.28 (58.275 rounds up)
      expect(lineTotalMinor(17500, 750), 13125);
      expect(lineTotalMinor(17500, 1250), 21875);
      expect(formatPkr(lineTotalMinor(13000, 250)), 'Rs 32.50');
      expect(formatPkr(lineTotalMinor(13000, 2500)), 'Rs 325.00');
      expect(formatPkr(lineTotalMinor(17500, 333)), 'Rs 58.28');
    });
  });

  group('picker stock rules', () {
    test('beyond stock: refused without negative stock, warned with it', () {
      final refused = checkMeasuredPick(product: _atta, quantity: 41000, allowNegativeStock: false);
      expect(refused.allowed, isFalse);
      expect(refused.error, 'Only 40 kg available.');
      final warned = checkMeasuredPick(product: _atta, quantity: 41000, allowNegativeStock: true);
      expect((warned.allowed, warned.warning), (true, 'Only 40 kg in stock.'));
      expect(checkMeasuredPick(product: _atta, quantity: 40000, allowNegativeStock: false).allowed, isTrue);
    });

    test('what is already in the bill counts against stock', () {
      final check = checkMeasuredPick(
        product: _atta, quantity: 1000, allowNegativeStock: false, alreadyInCart: 39500);
      expect(check.error, 'Only 500 g available.');
    });

    test('untracked stock never blocks; invalid quantities always do', () {
      const untracked = PosProduct(
        id: 'u', name: 'U', salePriceMinor: 100, stockQuantity: 0,
        stockTrackingEnabled: false, measureUnit: MeasureUnit.kg);
      expect(checkMeasuredPick(product: untracked, quantity: 5000, allowNegativeStock: false).allowed, isTrue);
      for (final q in [null, 0, -250, maxMeasureQuantity + 1]) {
        expect(checkMeasuredPick(product: _atta, quantity: q, allowNegativeStock: true).allowed, isFalse, reason: '$q');
      }
    });
  });

  group('cart', () {
    test('a measured product keeps one line; add, set and remove are exact', () {
      final cart = PosCart()
        ..addQuantity(_atta, 1000)
        ..addQuantity(_atta, 1500);
      expect(cart.lines.single.quantity, 2500);
      expect(cart.lines.single.totalMinor, 32500);
      cart.setQuantity('atta', 250);
      expect((cart.lines.single.quantity, cart.subtotalMinor), (250, 3250));
      cart.addQuantity(_oil, 750);
      expect(cart.toSaleLines().map((l) => (l.productId, l.quantity)), [('atta', 250), ('oil', 750)]);
      cart.setQuantity('atta', 0);
      expect(cart.lines.map((l) => l.product.id), ['oil']);
      cart.remove('oil');
      expect(cart.isEmpty, isTrue);
    });

    test('piece products behave as before', () {
      final cart = PosCart()
        ..add(_surf)
        ..add(_surf)
        ..increment('surf');
      expect(cart.lines.single.quantity, 3000);
      cart.decrement('surf');
      expect((cart.lines.single.quantity, cart.subtotalMinor), (2000, 70000));
    });
  });

  group('quantity picker', () {
    testWidgets('presets add in one tap with an exact quantity', (tester) async {
      await _pumpPickerHost(tester, _atta);
      expect(find.text('Rs 130.00/kg • Available 40 kg'), findsOneWidget);
      for (final label in ['250 g', '500 g', '1 kg', '2.5 kg', '10 kg', '20 kg', '40 kg']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.byKey(const ValueKey('measure-preset-2500')));
      await tester.pumpAndSettle();
      expect(_lastPick, 2500);
    });

    testWidgets('owner defaults are offered when no presets are configured', (tester) async {
      await _pumpPickerHost(tester, _oil);
      for (final label in ['250 ml', '500 ml', '1 L', '2 L', '5 L']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('custom kg and g entries show a live exact total', (tester) async {
      await _pumpPickerHost(tester, _atta);
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '2.5');
      await tester.pump();
      expect(find.text('Total Rs 325.00 for 2.5 kg'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('measure-unit-fraction')));
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '250');
      await tester.pump();
      expect(find.text('Total Rs 32.50 for 250 g'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('measure-confirm')));
      await tester.pumpAndSettle();
      expect(_lastPick, 250);
    });

    testWidgets('ml and L entries for a volume product', (tester) async {
      await _pumpPickerHost(tester, _oil);
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '1.25');
      await tester.pump();
      expect(find.text('Total Rs 218.75 for 1.25 L'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('measure-unit-fraction')));
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '750');
      await tester.pump();
      expect(find.text('Total Rs 131.25 for 750 ml'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('measure-confirm')));
      await tester.pumpAndSettle();
      expect(_lastPick, 750);
    });

    testWidgets('invalid, zero and excess precision cannot be confirmed', (tester) async {
      await _pumpPickerHost(tester, _atta);
      FilledButton confirm() => tester.widget(find.byKey(const ValueKey('measure-confirm')));
      for (final text in ['0', '1.2345', '00', '1001']) {
        await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), text);
        await tester.pump();
        expect(confirm().onPressed, isNull, reason: text);
      }
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '1.2345');
      await tester.pump();
      expect(find.byKey(const ValueKey('measure-picker-message')), findsOneWidget);
    });

    testWidgets('without negative stock, quantities beyond stock are disabled', (tester) async {
      await _pumpPickerHost(tester, _atta, allowNegativeStock: false, alreadyInCart: 30000);
      OutlinedButton preset(int q) => tester.widget(find.byKey(ValueKey('measure-preset-$q')));
      expect(preset(10000).onPressed, isNotNull, reason: 'exactly the remaining 10 kg');
      expect(preset(20000).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '10.5');
      await tester.pump();
      expect(find.text('Only 10 kg available.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('measure-confirm'))).onPressed, isNull);
    });

    testWidgets('with negative stock allowed, it warns but adds', (tester) async {
      await _pumpPickerHost(tester, _atta, alreadyInCart: 30000);
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '20');
      await tester.pump();
      expect(find.text('Only 10 kg in stock.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('measure-confirm')));
      await tester.pumpAndSettle();
      expect(_lastPick, 20000);
    });

    testWidgets('custom quantity disabled hides the custom entry', (tester) async {
      const presetsOnly = PosProduct(
        id: 'rice', name: 'Rice', salePriceMinor: 34000, stockQuantity: 25000,
        stockTrackingEnabled: true, measureUnit: MeasureUnit.kg,
        measurePresets: [1000, 5000], allowCustomQuantity: false);
      await _pumpPickerHost(tester, presetsOnly);
      expect(find.byKey(const ValueKey('measure-custom-input')), findsNothing);
      expect(find.byKey(const ValueKey('measure-confirm')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('measure-preset-5000')));
      await tester.pumpAndSettle();
      expect(_lastPick, 5000);
    });

    testWidgets('editing starts from the line quantity and sets it exactly', (tester) async {
      await _pumpPickerHost(tester, _atta, editing: 2500);
      expect(find.text('In bill: 2.5 kg'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '3');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('measure-confirm')));
      await tester.pumpAndSettle();
      expect(_lastPick, 3000);
    });

    for (final (size, keyboard) in const [
      (Size(1024, 600), 340.0),
      (Size(1280, 800), 420.0),
      (Size(1280, 400), 200.0),
      (Size(800, 1280), 420.0),
    ]) {
      testWidgets('keyboard overlay keeps the picker usable: $size kb $keyboard', (tester) async {
        await _pumpPickerHost(tester, _atta, size: size, keyboard: keyboard);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '2.5');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('measure-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('measure-confirm')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_lastPick, 2500);
      });
    }
  });

  group('POS add and bill', () {
    // Same lifecycle as tablet_ux_polish_test: the workspace is disposed at
    // the end of each test body, before the binding checks for timers.
    Future<AppDatabase> pumpPos(WidgetTester tester, {Size size = const Size(1280, 800), double keyboard = 0}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(MaterialApp(
        home: PosWorkspace(
          shopName: 'ALI Shop',
          cashierName: 'ahmed1',
          initialCatalog: const PosCatalogSnapshot(
            products: [_atta, _surf],
            categories: [],
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

    Future<void> disposePos(WidgetTester tester, AppDatabase db) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(db.close);
    }

    Finder card(String name) => find.ancestor(of: find.text(name), matching: find.byType(PosProductCard));
    Finder addOn(String name) => find.descendant(of: card(name), matching: find.text('Add'));
    final bill = find.byKey(const ValueKey('current-bill-panel'));

    testWidgets('measured card shows Rs/kg and readable stock', (tester) async {
      final db = await pumpPos(tester);
      expect(find.descendant(of: card('Atta'), matching: find.text('Rs 130.00/kg')), findsOneWidget);
      expect(find.descendant(of: card('Atta'), matching: find.text('Stock 40 kg')), findsOneWidget);
      expect(find.descendant(of: card('Surf'), matching: find.text('Rs 350.00')), findsOneWidget);
      await disposePos(tester, db);
    });

    testWidgets('picked quantities merge into one exact line; tap edits; remove clears', (tester) async {
      final db = await pumpPos(tester);
      await tester.tap(addOn('Atta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('measure-preset-1000')));
      await tester.pumpAndSettle();
      await tester.tap(addOn('Atta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('measure-preset-1000')));
      await tester.pumpAndSettle();
      final quantity = find.byKey(const ValueKey('cart-quantity-atta'));
      expect(find.descendant(of: quantity, matching: find.text('2 kg')), findsOneWidget, reason: 'one line, not two');
      expect(find.descendant(of: bill, matching: find.text('Atta')), findsOneWidget);
      expect(find.descendant(of: bill, matching: find.text('Rs 260.00')), findsWidgets);

      await tester.tap(quantity);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '2.5');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('measure-confirm')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: quantity, matching: find.text('2.5 kg')), findsOneWidget, reason: 'never truncated to 2');
      expect(find.descendant(of: bill, matching: find.text('× Rs 130.00/kg')), findsOneWidget);
      expect(find.descendant(of: bill, matching: find.text('Rs 325.00')), findsWidgets);
      expect(find.descendant(of: bill, matching: find.byIcon(Icons.add)), findsNothing, reason: 'no piece stepper');

      await tester.tap(find.descendant(of: bill, matching: find.text('Remove')));
      await tester.pumpAndSettle();
      expect(quantity, findsNothing);
      await disposePos(tester, db);
    });

    testWidgets('a cancelled picker adds nothing; piece Add is direct', (tester) async {
      final db = await pumpPos(tester);
      await tester.tap(addOn('Atta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart-quantity-atta')), findsNothing);
      await tester.tap(addOn('Surf'));
      await tester.pump();
      expect(find.byType(MeasuredQuantityPicker), findsNothing);
      expect(find.descendant(of: bill, matching: find.byIcon(Icons.add)), findsOneWidget, reason: 'piece stepper kept');
      expect(find.descendant(of: bill, matching: find.text('1')), findsOneWidget);
      await disposePos(tester, db);
    });

    for (final (size, keyboard) in const [(Size(1024, 600), 340.0), (Size(1340, 800), 380.0)]) {
      testWidgets('picker over the POS with keyboard open: $size kb $keyboard', (tester) async {
        final db = await pumpPos(tester, size: size, keyboard: keyboard);
        expect(tester.takeException(), isNull);
        final shellBefore = tester.getRect(find.byKey(const ValueKey('cashier-sidebar')));
        await tester.tap(addOn('Atta').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('measure-custom-input')), '1.25');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.byKey(const ValueKey('cashier-sidebar'))), shellBefore, reason: 'POS shell not resized');
        await tester.ensureVisible(find.byKey(const ValueKey('measure-confirm')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('measure-confirm')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await disposePos(tester, db);
      });
    }
  });

  group('receipt and Bills show measured units', () {
    testWidgets('receipt line reads 2.5 kg, a piece line a count', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReceiptView(
              receipt: ReceiptModel(
                shopName: 'S', reference: 'B-1', dateTime: DateTime.utc(2026, 10, 9),
                cashier: 'ahmed', subtotal: 60000, total: 60000, payments: const {'cash': 60000},
                lines: const [
                  ReceiptLine(name: 'Atta', quantity: 2500, unitPrice: 13000, total: 32500, measureUnit: MeasureUnit.kg),
                  ReceiptLine(name: 'Oil', quantity: 750, unitPrice: 17500, total: 13125, measureUnit: MeasureUnit.liter),
                  ReceiptLine(name: 'Surf', quantity: 1000, unitPrice: 14375, total: 14375),
                ],
              ),
            ),
          ),
        ),
      ));
      expect(find.text('2.5 kg × Atta  Rs 325.00'), findsOneWidget);
      expect(find.text('750 ml × Oil  Rs 131.25'), findsOneWidget);
      expect(find.text('1 × Surf  Rs 143.75'), findsOneWidget);
    });

    test('Bills detail reads the snapshot unit', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final at = DateTime.utc(2026, 10, 9);
      await db.into(db.shops).insert(ShopsCompanion.insert(
        id: 'shop', name: 'S', phone: '', address: '', subscriptionPlan: SubscriptionPlan.trial,
        subscriptionStatus: SubscriptionStatus.trial, createdAt: at, updatedAt: at));
      await db.into(db.devices).insert(DevicesCompanion.insert(
        id: 'd', shopId: 'shop', deviceName: 'd', deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: at));
      await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
        id: 'atta', shopId: 'shop', customName: const Value('Atta'), unit: const Value('kg'),
        sellMode: Value(SellMode.measured.name), purchasePrice: 12000, salePrice: 13000, createdAt: at, updatedAt: at));
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'sale', shopId: 'shop', cashierId: 'owner', deviceId: 'd', subtotal: 32500, discountTotal: 0,
        taxTotal: 0, grandTotal: 32500, paymentStatus: PaymentStatus.paid, saleStatus: SaleStatus.completed, createdAt: at));
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'i', shopId: 'shop', saleId: 'sale', productId: 'atta', productNameSnapshot: 'Atta', quantity: 2500,
        costPriceSnapshot: 12000, salePriceSnapshot: 13000, discountAmount: 0, lineTotal: 32500, createdAt: at,
        measureUnitSnapshot: const Value('kg')));
      final repository = DriftSalesHistoryRepository(db, shopId: 'shop');
      final row = (await repository.page(
        filter: SaleHistoryFilter(range: ReportRange(DateTime.utc(2026), DateTime.utc(2027), label: 'all')),
      )).single;
      final line = (await repository.detail(row)).lines.single;
      expect((line.quantity, line.measureUnit, line.total), (2500, MeasureUnit.kg, 32500));
      expect(formatLineQuantity(line.quantity, line.measureUnit), '2.5 kg');
    });
  });

  group('owner setup', () {
    Future<void> pumpDialog(WidgetTester tester, Widget dialog, void Function(Object?) onResult) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(await showDialog<Object>(context: context, builder: (_) => dialog)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, String key, String text) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.enterText(find.byKey(ValueKey(key)), text);
      await tester.pump();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)).first);
      await tester.pumpAndSettle();
    }

    testWidgets('creates a loose kg product: Atta Rs 130/kg, 40 kg, presets', (tester) async {
      Object? result;
      await pumpDialog(tester, const CustomProductDialog(categories: [ProductCategory(id: 'staples', name: 'Staples')]), (r) => result = r);
      await tapKey(tester, 'selling-loose');
      expect(find.text('Weight (kg)'), findsOneWidget);
      expect(find.text('Pack size / label'), findsNothing);
      await fill(tester, 'custom-product-name', 'Atta');
      await tapKey(tester, 'custom-product-category');
      await tester.tap(find.text('Staples').last);
      await tester.pumpAndSettle();
      await fill(tester, 'custom-product-purchase', '120');
      await fill(tester, 'custom-product-sale', '130');
      await fill(tester, 'custom-product-opening', '40');
      await fill(tester, 'custom-product-low', '5');
      expect(find.text('Sale price per kg *'), findsOneWidget);
      // Defaults 250 g … 5 kg: drop 250 g, 2 kg; add 10, 20 and 40 kg.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('preset-chip-250')), matching: find.byTooltip('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('preset-chip-2000')), matching: find.byTooltip('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('custom-product-presets')), matching: find.text('kg')));
      await tester.pumpAndSettle();
      for (final kg in ['10', '20', '40']) {
        await fill(tester, 'preset-input', kg);
        await tapKey(tester, 'preset-add');
      }
      await tapKey(tester, 'custom-product-create');
      final input = (result! as CustomProductDraft).input;
      expect((input.sellMode, input.unit, input.salePriceMinor, input.purchasePriceMinor),
          (SellMode.measured, ProductUnit.kg, 13000, 12000));
      expect((input.openingQuantity, input.lowStockLevel), (40000, 5000));
      expect(input.measurePresets, [500, 1000, 5000, 10000, 20000, 40000]);
      expect((input.allowCustomQuantity, input.packLabel), (true, null));
    });

    testWidgets('creates a loose litre product with custom quantity off', (tester) async {
      Object? result;
      await pumpDialog(tester, const CustomProductDialog(categories: [ProductCategory(id: 'oil', name: 'Cooking')]), (r) => result = r);
      await tapKey(tester, 'selling-loose');
      await tapKey(tester, 'measure-liter');
      await fill(tester, 'custom-product-name', 'Loose oil');
      await tapKey(tester, 'custom-product-category');
      await tester.tap(find.text('Cooking').last);
      await tester.pumpAndSettle();
      await fill(tester, 'custom-product-purchase', '160');
      await fill(tester, 'custom-product-sale', '175');
      await fill(tester, 'custom-product-opening', '20.5');
      expect(find.text('Opening stock (L)'), findsOneWidget);
      await tapKey(tester, 'custom-product-allow-custom');
      await tapKey(tester, 'custom-product-create');
      final input = (result! as CustomProductDraft).input;
      expect((input.unit, input.openingQuantity, input.allowCustomQuantity),
          (ProductUnit.liter, 20500, false));
      expect(input.measurePresets, defaultMeasurePresets);
    });

    testWidgets('the piece form is unchanged', (tester) async {
      Object? result;
      await pumpDialog(tester, const CustomProductDialog(categories: [ProductCategory(id: 'h', name: 'Household')]), (r) => result = r);
      expect(find.text('Pack size / label'), findsOneWidget);
      expect(find.byKey(const ValueKey('custom-product-presets')), findsNothing);
      await fill(tester, 'custom-product-name', 'Surf');
      await tapKey(tester, 'custom-product-category');
      await tester.tap(find.text('Household').last);
      await tester.pumpAndSettle();
      await fill(tester, 'custom-product-purchase', '300');
      await fill(tester, 'custom-product-sale', '350');
      await tapKey(tester, 'custom-product-create');
      final input = (result! as CustomProductDraft).input;
      expect((input.sellMode, input.unit, input.allowCustomQuantity), (SellMode.piece, ProductUnit.piece, true));
      expect(input.measurePresets, isNull);
    });

    testWidgets('editing a loose product changes prices, presets and custom only', (tester) async {
      ProductEdit? saved;
      const product = ManagedProduct(
        id: 'atta', name: 'Atta', categoryName: 'Staples', unit: 'kg', purchasePriceMinor: 12000,
        salePriceMinor: 13000, stockQuantity: 37500, lowStockLevel: 5000, isActive: true, isCustom: true,
        sellMode: SellMode.measured, measurePresets: [500, 1000], allowCustomQuantity: true);
      await pumpDialog(tester, EditProductDialog(product: product, onSubmit: (edit) async => saved = edit), (_) {});
      expect(find.text('Loose product · sold by weight (kg)'), findsOneWidget);
      expect(find.text('Sale price per kg'), findsOneWidget);
      await fill(tester, 'edit-product-sale', '135');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('edit-product-presets')), matching: find.text('kg')));
      await tester.pumpAndSettle();
      await fill(tester, 'preset-input', '5');
      await tapKey(tester, 'preset-add');
      await tapKey(tester, 'edit-product-allow-custom');
      await tapKey(tester, 'edit-product-save');
      expect((saved!.salePriceMinor, saved!.purchasePriceMinor, saved!.lowStockLevel),
          (13500, 12000, 5000));
      expect(saved!.measurePresets, [500, 1000, 5000]);
      expect(saved!.allowCustomQuantity, isFalse);
    });

    testWidgets('editing a piece product sends no measured settings', (tester) async {
      ProductEdit? saved;
      const product = ManagedProduct(
        id: 'surf', name: 'Surf', categoryName: 'H', unit: 'piece', purchasePriceMinor: 30000,
        salePriceMinor: 35000, stockQuantity: 9000, lowStockLevel: 0, isActive: true, isCustom: true);
      await pumpDialog(tester, EditProductDialog(product: product, onSubmit: (edit) async => saved = edit), (_) {});
      expect(find.byKey(const ValueKey('edit-product-presets')), findsNothing);
      await tapKey(tester, 'edit-product-save');
      expect((saved!.measurePresets, saved!.allowCustomQuantity), (null, null));
    });

    testWidgets('the preset editor keeps 1 to 8 distinct valid quantities', (tester) async {
      Object? result;
      await pumpDialog(tester, const CustomProductDialog(categories: [ProductCategory(id: 's', name: 'S')]), (r) => result = r);
      await tapKey(tester, 'selling-loose');
      for (final grams in ['100', '200', '300']) {
        await fill(tester, 'preset-input', grams);
        await tapKey(tester, 'preset-add');
      }
      expect(find.byKey(const ValueKey('preset-input')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('preset-input'))).enabled, isFalse, reason: '8 reached');
      for (final q in [100, 200, 300, 250, 500, 1000, 2000]) {
        await tester.tap(find.descendant(of: find.byKey(ValueKey('preset-chip-$q')), matching: find.byTooltip('Remove')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('preset-chip-5000')), matching: find.byTooltip('Remove')));
      await tester.pumpAndSettle();
      expect(find.text('Keep at least one quick quantity.'), findsOneWidget);
      await fill(tester, 'preset-input', '5000');
      await tapKey(tester, 'preset-add');
      expect(find.text('That quick quantity is already in the list.'), findsOneWidget);
      await fill(tester, 'preset-input', '0');
      await tapKey(tester, 'preset-add');
      expect(find.text('Quantity must be more than zero.'), findsOneWidget);
      expect(result, isNull);
    });
  });

  group('owner service and local catalog', () {
    test('loose create validates and sends one product and one opening movement', () async {
      final gateway = _RecordingGateway();
      final service = ProductManagementService(gateway, _SeqIds());
      CustomProductInput input({ProductUnit unit = ProductUnit.kg, List<int>? presets = const [500, 1000]}) =>
          CustomProductInput(
            name: 'Atta', categoryId: 'c', unit: unit, purchasePriceMinor: 12000, salePriceMinor: 13000,
            openingQuantity: 40000, lowStockLevel: 5000, sellMode: SellMode.measured,
            measurePresets: presets, allowCustomQuantity: true);
      await service.createCustom(shopId: 'shop', deviceId: 'd', input: input());
      expect(gateway.calls, [('id-1', 'id-2', 40000)]);
      for (final bad in [
        input(unit: ProductUnit.piece),
        input(unit: ProductUnit.gram),
        input(presets: [for (var i = 1; i <= 9; i++) i * 100]),
        input(presets: [500, 500]),
        input(presets: [0]),
      ]) {
        expect(() => service.createCustom(shopId: 'shop', deviceId: 'd', input: bad),
            throwsA(isA<ProductValidationException>()));
      }
      expect(gateway.calls, hasLength(1), reason: 'nothing sent for invalid setups');
    });

    test('the local catalog and product list read the owner setup', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final at = DateTime.utc(2026, 10, 9);
      await db.into(db.shops).insert(ShopsCompanion.insert(
        id: 'shop', name: 'S', phone: '', address: '', subscriptionPlan: SubscriptionPlan.trial,
        subscriptionStatus: SubscriptionStatus.trial, createdAt: at, updatedAt: at,
        allowNegativeStock: const Value(false)));
      await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
        id: 'atta', shopId: 'shop', customName: const Value('Atta'), unit: const Value('kg'),
        sellMode: Value(SellMode.measured.name), measurePresets: const Value('[500,1000,5000]'),
        allowCustomQuantity: const Value(false), purchasePrice: 12000, salePrice: 13000, createdAt: at, updatedAt: at));
      await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
        id: 'surf', shopId: 'shop', customName: const Value('Surf'), purchasePrice: 30000, salePrice: 35000,
        createdAt: at, updatedAt: at));
      final snapshot = await DriftPosCatalog(db, shopId: 'shop').load();
      expect(snapshot.allowNegativeStock, isFalse);
      final atta = snapshot.products.firstWhere((p) => p.id == 'atta');
      expect((atta.measureUnit, atta.allowCustomQuantity), (MeasureUnit.kg, false));
      expect(atta.measurePresets, [500, 1000, 5000]);
      final surf = snapshot.products.firstWhere((p) => p.id == 'surf');
      expect((surf.isMeasured, surf.allowCustomQuantity), (false, true));
      expect(surf.measurePresets, isEmpty);
      final managed = await DriftProductManagementRepository(db, shopId: 'shop').products();
      final attaManaged = managed.firstWhere((p) => p.id == 'atta');
      expect((attaManaged.sellMode, attaManaged.measureUnit, attaManaged.allowCustomQuantity),
          (SellMode.measured, MeasureUnit.kg, false));
      expect(attaManaged.measurePresets, [500, 1000, 5000]);
    });
  });
}

final class _SeqIds implements IdGenerator {
  var n = 0;
  @override
  String next() => 'id-${++n}';
}

final class _RecordingGateway implements ProductManagementGateway {
  final calls = <(String, String, int)>[];
  @override
  Future<String> createCustomProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required CustomProductInput input,
  }) async {
    calls.add((shopProductId, movementId, input.openingQuantity));
    return shopProductId;
  }

  @override
  Future<String> addMasterProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required String masterProductId,
    required AddProductInput input,
  }) => throw UnimplementedError();

  @override
  Future<List<MasterCatalogItem>> searchMasterCatalog({required String shopId, required String query}) async => [];

  @override
  Future<void> updateProduct({
    required String shopId,
    required String productId,
    required int purchasePriceMinor,
    required int salePriceMinor,
    required int lowStockLevel,
    required bool isActive,
    List<int>? measurePresets,
    bool? allowCustomQuantity,
  }) async {}
}

final class _Committer implements PosSaleCommitter {
  @override
  Future<CreatedSale> complete(String checkoutId, PosCart cart, PosPaymentPlan payment) =>
      throw UnimplementedError();
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
