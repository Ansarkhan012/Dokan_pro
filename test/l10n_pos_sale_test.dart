// Stage 2B Batch 2: the cashier sale in Urdu. A real offline checkout
// (local Drift database, upload failing) of a PIECE, loose kg, loose ml, a
// pack size, an Urdu-named and an English-named product, entered by card,
// pack picker, Urdu-digit quantities and the hardware scanner, with real
// Roboto + Noto Nastaliq/Naskh metrics at 1340x800, 1024x600 and 600x960 and
// text scale 1.0 / 1.3. Totals and stock equal the English run exactly.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/format/measure_format.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/core/l10n/messages.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart' show PosWorkspace;
import 'package:dukaan_pro/features/receipts/receipt_model.dart';
import 'package:dukaan_pro/features/receipts/receipt_printer.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_r1/support/pos_fixture.dart';
import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));

const _dairy = 'd0000000-0000-0000-0000-000000000003';

/// Coke 180.00 + Atta 2.5 kg x 130.00 + Oil 500 ml x 175.00/L + Tapal 250 g
/// 410.00 + سرف ایکسل 350.00 + Lux Soap (Large) 95.00.
const _expectedTotal = 18000 + 32500 + 8750 + 41000 + 35000 + 9500;

void main() {
  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('message and category mappers', () {
    test('every checkout, payment and quantity message has a translation', () {
      const domain = [
        'Cart must not be empty',
        'Discount cannot be negative',
        'Discount exceeds line value',
        'Insufficient stock',
        'Product requires a display name',
        'Sale total cannot be negative',
        'Shop does not exist',
        'Cashier is not active for this shop',
        'Credit customer is not active for this shop',
        'Credit payment requires a customer',
        'Customer credit limit exceeded',
        'Device is not active for this shop',
        'Measured product requires kg or liter',
        'Payment amounts must be greater than zero',
        'Payment total must equal sale total',
        'Piece products are sold in whole units',
        'Product is not active for this shop',
        'Product prices cannot be negative',
        'Quantities must be greater than zero',
      ];
      final payment = [
        const PosPaymentPlan(payments: []).validate(100),
        const PosPaymentPlan(
          payments: [PosPayment(method: PaymentMethod.cash, amountMinor: 50)],
        ).validate(100),
        const PosPaymentPlan(
          payments: [
            PosPayment(method: PaymentMethod.credit, amountMinor: 100),
          ],
        ).validate(100),
        const PosPaymentPlan(
          payments: [PosPayment(method: PaymentMethod.cash, amountMinor: 100)],
          cashReceivedMinor: 50,
        ).validate(100),
      ];
      final quantity = [
        measureQuantityError(null),
        measureQuantityError(0),
        measureQuantityError(maxMeasureQuantity + 1),
      ];
      for (final message in [...domain, ...payment, ...quantity]) {
        expect(message, isNotNull);
        // English is byte-for-byte the domain text; Urdu is a translation.
        expect(localizedKnownMessage(_en, message!), message, reason: message);
        final urdu = localizedKnownMessage(_ur, message);
        expect(urdu, isNot(message), reason: message);
        expect(RegExp('[a-zA-Z]').hasMatch(urdu!), isFalse, reason: urdu);
      }
      // Unknown messages keep their English detail; English stays unchanged.
      expect(localizedSaleError(_en, 'Odd failure'), 'Odd failure');
      expect(localizedSaleError(_ur, 'Odd failure'), contains('Odd failure'));
      expect(localizedMessage(_ur, 'anything else'), 'anything else');
    });

    test(
      'the unavailable printer message is translated, printer untouched',
      () async {
        final result = await const UnavailableReceiptPrinter().print(
          ReceiptModel(
            shopName: 'S',
            reference: 'B-1',
            dateTime: DateTime.utc(2026, 10, 12),
            cashier: 'c',
            lines: const [],
            subtotal: 0,
            total: 0,
            payments: const {},
          ),
          paperWidth: ReceiptPaperWidth.mm58,
        );
        expect(localizedMessage(_en, result.message), result.message);
        expect(
          localizedMessage(_ur, result.message),
          _ur.receiptPrinterMissing,
        );
      },
    );

    test('built-in categories by id; shop categories exactly as entered', () {
      const seeded = {
        'd0000000-0000-0000-0000-000000000001': ('Household', 'گھریلو اشیاء'),
        'd0000000-0000-0000-0000-000000000002': ('Staples', 'راشن'),
        'd0000000-0000-0000-0000-000000000003': ('Dairy', 'دودھ اور ڈیری'),
        'd0000000-0000-0000-0000-000000000004': (
          'Cooking Essentials',
          'کھانا پکانے کا سامان',
        ),
        'd0000000-0000-0000-0000-000000000005': ('Beverages', 'مشروبات'),
        'd0000000-0000-0000-0000-000000000006': ('Snacks', 'اسنیکس'),
      };
      for (final MapEntry(key: id, value: (english, urdu)) in seeded.entries) {
        expect(localizedCategoryName(_en, id, english), english);
        expect(localizedCategoryName(_ur, id, english), urdu);
      }
      // A shop's own category (any other id) is never translated.
      expect(localizedCategoryName(_ur, 'shop-cat', 'Pan Items'), 'Pan Items');
      expect(
        localizedCategoryName(_ur, 'shop-cat', 'پان کا سامان'),
        'پان کا سامان',
      );
      expect(localizedCategoryName(_en, 'shop-cat', 'Household'), 'Household');
    });
  });

  group('Urdu offline sale end to end (real fonts)', () {
    for (final (size, font, scale) in const [
      (Size(1340, 800), UrduFont.nastaliq, 1.0),
      (Size(1340, 800), UrduFont.naskh, 1.0),
      (Size(1024, 600), UrduFont.nastaliq, 1.0),
      (Size(1024, 600), UrduFont.naskh, 1.0),
      (Size(600, 960), UrduFont.nastaliq, 1.0),
      (Size(600, 960), UrduFont.naskh, 1.0),
      (Size(1340, 800), UrduFont.nastaliq, 1.3),
      (Size(1024, 600), UrduFont.nastaliq, 1.3),
      (Size(600, 960), UrduFont.naskh, 1.3),
    ]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} ${font.name} x$scale',
        (tester) async {
          final h = await _open(tester, size, scale);
          final controller = LocaleController(
            initialLocale: LocaleController.urdu,
            initialUrduFont: font,
          );
          await _pumpPos(tester, h, controller);
          final l10n = _ur;

          // Urdu chrome; built-in category translated, the shop's own as typed.
          expect(find.text(l10n.posSearchHint), findsOneWidget);
          expect(find.text(isolateAuto('دودھ اور ڈیری')), findsOneWidget);
          expect(find.text(isolateAuto('Pan Items')), findsOneWidget);

          await _fillCart(tester);
          await _openBillIfNarrow(tester);
          // Loose lines show Urdu units with Western digits, kept LTR.
          expect(find.text(isolateLtr('2.5 کلو')), findsOneWidget);
          expect(find.text(isolateLtr('500 ملی لیٹر')), findsOneWidget);
          // Mixed names keep their own direction and exact text.
          expect(find.text(isolateAuto('سرف ایکسل')), findsWidgets);
          expect(find.text(isolateAuto('Lux Soap (Large)')), findsWidgets);
          // A short bill panel builds its lines lazily: scroll to the pack line.
          final tapal = find.text(isolateAuto('Tapal Danedar 250 g'));
          await tester.scrollUntilVisible(
            tapal,
            40,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('current-bill-panel')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(tapal, findsWidgets);
          expect(
            find.text(l10n.posPay(isolateLtr(formatPkr(_expectedTotal)))),
            findsOneWidget,
          );

          // Switching language keeps every line: the total is the exact sum of
          // all six lines.
          await controller.setLocale(LocaleController.english);
          await tester.pumpAndSettle();
          expect(find.text('Pay ${formatPkr(_expectedTotal)}'), findsOneWidget);
          await controller.setLocale(LocaleController.urdu);
          await tester.pumpAndSettle();

          // Offline checkout (the upload fails; the sale is saved locally).
          await tester.tap(find.byKey(const ValueKey('pay-button')));
          await tester.pumpAndSettle();
          expect(
            find.text(l10n.payTitle(isolateLtr(formatPkr(_expectedTotal)))),
            findsOneWidget,
          );
          expect(find.text(l10n.paymentUdhaar), findsOneWidget);
          await tester.tap(find.text(l10n.payComplete));
          await _settle(tester);
          expect(find.text(l10n.saleCompleted), findsOneWidget);
          expect(find.text(l10n.saleSavedWaiting), findsOneWidget);
          expect(find.textContaining('2.5 کلو'), findsWidgets);
          expect(
            find.textContaining('@ ${isolateLtr('Rs 130.00')} فی کلو'),
            findsOneWidget,
          );
          expect(
            find.textContaining(l10n.receiptEach(isolateLtr('Rs 350.00'))),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await _assertSaved(tester, h);
          await _dispose(tester, h);
        },
      );
    }

    testWidgets('English run: same sale, same totals, unchanged text', (
      tester,
    ) async {
      final h = await _open(tester, const Size(1340, 800), 1.0);
      await _pumpPos(tester, h, LocaleController());
      await _fillCart(tester, english: true);
      expect(find.text('2.5 kg'), findsOneWidget);
      expect(find.text('500 ml'), findsOneWidget);
      expect(find.text('Pay ${formatPkr(_expectedTotal)}'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pay-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Payment • ${formatPkr(_expectedTotal)}'),
        findsOneWidget,
      );
      await tester.tap(find.text('Complete Sale'));
      await _settle(tester);
      expect(find.text('Sale completed'), findsOneWidget);
      expect(find.text('2.5 kg × Atta  Rs 325.00'), findsOneWidget);
      expect(find.text('  @ Rs 130.00/kg'), findsOneWidget);
      expect(find.text('500 ml × Oil  Rs 87.50'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _assertSaved(tester, h);
      await _dispose(tester, h);
    });

    testWidgets('Urdu measured picker: Urdu digits, units and stock refusal', (
      tester,
    ) async {
      final h = await _open(tester, const Size(1340, 800), 1.0);
      await (h.db.update(h.db.shops)..where((t) => t.id.equals(shopId))).write(
        const ShopsCompanion(allowNegativeStock: Value(false)),
      );
      await _pumpPos(
        tester,
        h,
        LocaleController(initialLocale: LocaleController.urdu),
      );
      await _tapProduct(tester, 'Atta');
      expect(find.text(_ur.measureCustomQuantity), findsOneWidget);
      expect(find.text('کلو'), findsOneWidget);
      expect(find.text('گرام'), findsOneWidget);
      // 40 kg in stock: 45 kg typed with Urdu digits is refused in Urdu.
      await tester.enterText(
        find.byKey(const ValueKey('measure-custom-input')),
        '۴۵',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('measure-custom-input')),
            )
            .controller!
            .text,
        '45',
      );
      expect(
        find.text(_ur.measureOnlyAvailable(isolateLtr('40 کلو'))),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('measure-confirm')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('measure-custom-input')),
        '۱٫۲۵',
      );
      await tester.pump();
      expect(
        find.text(
          _ur.measureTotalFor(isolateLtr('Rs 162.50'), isolateLtr('1.25 کلو')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(_ur.commonCancel));
      await tester.pumpAndSettle();
      await _dispose(tester, h);
    });
  });
}

Future<PosHarness> _open(WidgetTester tester, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final h = await PosHarness.open(mode: GatewayMode.fail);
  await _seedCatalog(h.db);
  return h;
}

Future<void> _seedCatalog(AppDatabase db) async {
  final t = DateTime.utc(2026, 9, 1);
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: _dairy,
          name: 'Dairy',
          createdAt: t,
          updatedAt: t,
        ),
      );
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: 'shop-cat',
          shopId: const Value(shopId),
          name: 'Pan Items',
          createdAt: t,
          updatedAt: t,
        ),
      );
  Future<void> product(
    String id,
    String name,
    int price, {
    String? unit,
    String? family,
    String? pack,
    String? barcode,
    String? category,
    int stock = 40000,
  }) async {
    await db
        .into(db.shopProducts)
        .insert(
          ShopProductsCompanion.insert(
            id: id,
            shopId: shopId,
            customName: Value(name),
            unit: Value(unit ?? 'piece'),
            sellMode: Value(
              unit == null ? SellMode.piece.name : SellMode.measured.name,
            ),
            allowCustomQuantity: const Value(true),
            familyId: Value(family),
            packLabel: Value(pack),
            barcode: Value(barcode),
            categoryId: Value(category),
            purchasePrice: price - 1000 < 0 ? 0 : price - 1000,
            salePrice: price,
            createdAt: t,
            updatedAt: t,
          ),
        );
    await db
        .into(db.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: 'open-$id',
            shopId: shopId,
            productId: id,
            type: InventoryMovementType.openingStock,
            quantity: stock,
            createdBy: ownerId,
            createdAt: t,
          ),
        );
  }

  await product('atta', 'Atta', 13000, unit: 'kg');
  await product('oil', 'Oil', 17500, unit: 'liter', category: _dairy);
  await product(
    'tapal-250',
    'Tapal Danedar',
    41000,
    family: 'family-tapal',
    pack: '250 g',
  );
  await product(
    'tapal-500',
    'Tapal Danedar',
    80000,
    family: 'family-tapal',
    pack: '500 g',
  );
  await product('surf-ur', 'سرف ایکسل', 35000, category: 'shop-cat');
  await product('lux', 'Lux Soap (Large)', 9500, barcode: '8964000000555');
}

Future<void> _pumpPos(
  WidgetTester tester,
  PosHarness h,
  LocaleController c,
) async {
  final catalog = await DriftPosCatalog(h.db, shopId: shopId).load();
  await tester.pumpWidget(
    LocalizedMaterialApp(
      controller: c,
      home: PosWorkspace(
        shopName: 'Ali Shop',
        cashierName: 'ahmed1',
        initialCatalog: catalog,
        committer: h.committer,
        salesHistory: DriftSalesHistoryRepository(h.db, shopId: shopId),
        offline: true,
        initialHasPendingSync: false,
        onLogout: () async {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tapProduct(
  WidgetTester tester,
  String name, {
  bool english = false,
}) async {
  final finder = find.text(english ? name : isolateAuto(name)).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillCart(WidgetTester tester, {bool english = false}) async {
  await _tapProduct(tester, 'Coke', english: english);
  // 2.5 kg typed with Urdu digits (the field shows and parses 2.5).
  await _tapProduct(tester, 'Atta', english: english);
  await tester.enterText(
    find.byKey(const ValueKey('measure-custom-input')),
    '۲٫۵',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('measure-confirm')));
  await tester.pumpAndSettle();
  // 500 ml in the fraction unit.
  await _tapProduct(tester, 'Oil', english: english);
  await tester.tap(find.byKey(const ValueKey('measure-unit-fraction')));
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('measure-custom-input')),
    '۵۰۰',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('measure-confirm')));
  await tester.pumpAndSettle();
  // One 250 g pack from the family picker.
  final family = find.byKey(const ValueKey('family-card-family-tapal'));
  await tester.ensureVisible(family);
  await tester.pumpAndSettle();
  await tester.tap(family);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('pack-pick-tapal-250')));
  await tester.pumpAndSettle();
  await _tapProduct(tester, 'سرف ایکسل', english: english);
  // The hardware scanner adds Lux Soap.
  for (final digit in '8964000000555'.split('')) {
    await tester.sendKeyEvent(
      LogicalKeyboardKey(0x30 + int.parse(digit)),
      character: digit,
    );
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

Future<void> _openBillIfNarrow(WidgetTester tester) async {
  final open = find.byKey(const ValueKey('open-cart-button'));
  if (open.evaluate().isEmpty) return;
  await tester.tap(open);
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _assertSaved(WidgetTester tester, PosHarness h) async {
  final sales = await h.db.select(h.db.sales).get();
  expect(sales, hasLength(1));
  expect(sales.single.grandTotal, _expectedTotal);
  expect(await h.stock(cokeId), openingStock - 1000);
  expect(await h.stock('atta'), 40000 - 2500);
  expect(await h.stock('oil'), 40000 - 500);
  expect(await h.stock('tapal-250'), 40000 - 1000);
  expect(await h.stock('tapal-500'), 40000); // independent pack stock
  expect(await h.stock('surf-ur'), 40000 - 1000);
  expect(await h.stock('lux'), 40000 - 1000);
  // Saved offline: the outbox still holds it for upload.
  expect(
    (await h.outbox()).where((o) => o.entityId == sales.single.id),
    isNotEmpty,
  );
}

Future<void> _dispose(WidgetTester tester, PosHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  await h.db.close();
}
