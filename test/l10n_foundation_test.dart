// Stage 2B Batch 0: localization foundation. English stays the default;
// Urdu switches the whole app to RTL without restarting, signing out or
// losing the cart; the choice persists per device; Urdu/Arabic digits typed
// at numeric boundaries become Western digits before any parser.
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/dukaan_pro_app.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/format/measure_format.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/digits.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/language_switcher.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/products/custom_product_dialog.dart'
    show moneyField;
import 'package:dukaan_pro/features/products/pack_family_editor.dart'
    show parseWholePacks;
import 'package:dukaan_pro/features/products/product_management_native.dart'
    as products
    show parseQuantity;
import 'package:dukaan_pro/features/purchases/purchase_management_native.dart'
    as purchases
    show parseQuantity;
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/real_fonts.dart';

const _surf = PosProduct(
  id: 'surf',
  name: 'Surf',
  salePriceMinor: 35000,
  stockQuantity: 9000,
  stockTrackingEnabled: true,
  barcode: '8964000000017',
  categoryId: 'household',
);
const _tea = PosProduct(
  id: 'tea',
  name: 'Tea',
  salePriceMinor: 29000,
  stockQuantity: 9000,
  stockTrackingEnabled: true,
  barcode: '8964000000024',
  categoryId: 'household',
);

final _bill = find.byKey(const ValueKey('current-bill-panel'));
final _switcher = find.byKey(const ValueKey('language-switcher'));

void main() {
  // Real Roboto + Urdu metrics, so layout checks mean what they say.
  setUpAll(loadRealFonts);

  group('digit normalization', () {
    test('Urdu and Arabic digits and separators become ASCII', () {
      expect(normalizeDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(normalizeDigits('۲٫۵'), '2.5');
      expect(normalizeDigits('۱٬۲۵۰'), '1,250');
      expect(normalizeDigits('Rs ۳۵۰'), 'Rs 350');
      expect(normalizeDigits('۱۲۳۴').length, 4);
    });

    test('ASCII and other text are returned unchanged (same instance)', () {
      const ascii = 'Rs 1025.50 - 8964000000017';
      expect(identical(normalizeDigits(ascii), ascii), isTrue);
      expect(normalizeDigits('چائے 250 گرام'), 'چائے 250 گرام');
    });

    test('the formatter keeps the cursor and runs before digitsOnly', () {
      const typed = TextEditingValue(
        text: '۱۲۳۴',
        selection: TextSelection.collapsed(offset: 4),
      );
      final ascii = const AsciiDigitsFormatter().formatEditUpdate(
        TextEditingValue.empty,
        typed,
      );
      expect(ascii.text, '1234');
      expect(ascii.selection, typed.selection);
      final filtered = FilteringTextInputFormatter.digitsOnly.formatEditUpdate(
        TextEditingValue.empty,
        ascii,
      );
      expect(filtered.text, '1234');
      // The old behaviour this prevents: digitsOnly alone drops Urdu digits.
      expect(
        FilteringTextInputFormatter.digitsOnly
            .formatEditUpdate(TextEditingValue.empty, typed)
            .text,
        isEmpty,
      );
    });

    test('every numeric parser accepts Urdu digits with unchanged results', () {
      expect(parseMoneyMinor('۱۲۵۰٫۵۰'), 125050);
      expect(parseMoneyMinor('1250.50'), 125050);
      expect(parseMoneyMinor('abc'), isNull);
      expect(parseMeasureInput('۲٫۵', fractionUnit: false), 2500);
      expect(parseMeasureInput('2.5', fractionUnit: false), 2500);
      expect(parseMeasureInput('۷۵۰', fractionUnit: true), 750);
      expect(parseMeasureInput('۲٫۵۰۰۱', fractionUnit: false), isNull);
      expect(parseWholePacks('۲۴'), 24000);
      expect(parseWholePacks('24'), 24000);
      expect(products.parseQuantity('۳'), 3000);
      expect(products.parseQuantity('1.25'), 1250);
      expect(purchases.parseQuantity('۱٫۲۵'), 1250);
      expect(purchases.parseQuantity('-1'), isNull);
    });

    testWidgets('a real money field shows and keeps Western digits', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: moneyField(controller, 'Sale price'))),
      );
      await tester.enterText(find.byType(TextField), '۳۵۰٫۵۰');
      expect(controller.text, '350.50');
      expect(parseMoneyMinor(controller.text), 35050);
    });
  });

  group('bidi helpers', () {
    test('isolates wrap text; direction follows the first strong letter', () {
      expect(
        isolateLtr('Rs 50.00'),
        '${leftToRightIsolate}Rs 50.00$popDirectionalIsolate',
      );
      expect(textDirectionOf('Surf Excel'), TextDirection.ltr);
      expect(textDirectionOf('سرف ایکسل'), TextDirection.rtl);
      expect(textDirectionOf('250 چائے'), TextDirection.rtl);
      expect(textDirectionOf('8964000000017'), isNull);
      expect(textDirectionOf(''), isNull);
    });

    testWidgets('money, quantities and ids are isolated only in RTL', (
      tester,
    ) async {
      late BuildContext ltr, rtl;
      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.ltr,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder: (c) {
                  ltr = c;
                  return const SizedBox();
                },
              ),
            ),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (c) {
                  rtl = c;
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      );
      expect(bidiMoney(ltr, '-Rs 50.00'), '-Rs 50.00');
      expect(bidiQuantity(ltr, '2.5 kg'), '2.5 kg');
      expect(bidiId(ltr, 'B-0001'), 'B-0001');
      expect(bidiMoney(rtl, '-Rs 50.00'), isolateLtr('-Rs 50.00'));
      expect(bidiQuantity(rtl, '2.5 kg'), isolateLtr('2.5 kg'));
      expect(bidiId(rtl, '8964000000017'), isolateLtr('8964000000017'));
    });
  });

  group('locale controller and persistence', () {
    test('English is the default for existing users', () async {
      final controller = await LocaleController.load(MemoryLocaleStore());
      expect(controller.locale, LocaleController.english);
      expect(controller.isUrdu, isFalse);
      expect(controller.urduFont, UrduFont.nastaliq);
    });

    test('a saved Urdu choice and font are restored after restart', () async {
      final store = MemoryLocaleStore();
      final first = await LocaleController.load(store);
      await first.setLocale(LocaleController.urdu);
      await first.setUrduFont(UrduFont.naskh);
      expect(store.values, {'ui_locale': 'ur', 'ui_urdu_font': 'naskh'});
      final restarted = await LocaleController.load(store);
      expect(restarted.locale, LocaleController.urdu);
      expect(restarted.urduFont, UrduFont.naskh);
    });

    test('unknown or unreadable preferences fall back to English', () async {
      expect(
        (await LocaleController.load(
          MemoryLocaleStore({'ui_locale': 'fr', 'ui_urdu_font': 'x'}),
        )).locale,
        LocaleController.english,
      );
      final broken = await LocaleController.load(_ThrowingStore());
      expect(broken.locale, LocaleController.english);
    });

    test('switching notifies at once even if saving fails', () async {
      final controller = LocaleController(store: _ThrowingStore());
      var notified = 0;
      controller.addListener(() => notified++);
      await controller.setLocale(LocaleController.urdu);
      await controller.setLocale(LocaleController.urdu); // no-op
      expect((controller.isUrdu, notified), (true, 1));
      await controller.setLocale(const Locale('fr'));
      expect(controller.locale, LocaleController.english);
    });
  });

  group('app shell', () {
    testWidgets(
      'English default: LTR, English Material text, theme unchanged',
      (tester) async {
        await tester.pumpWidget(const DukaanProApp());
        final context = tester.element(find.byType(Scaffold));
        expect(Directionality.of(context), TextDirection.ltr);
        expect(Localizations.localeOf(context), LocaleController.english);
        expect(MaterialLocalizations.of(context).okButtonLabel, 'OK');
        expect(
          Theme.of(context).textTheme.bodyMedium!.fontFamilyFallback,
          isNull,
        );
        expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
      },
    );

    testWidgets('a saved Urdu choice starts the app in RTL with Urdu fonts', (
      tester,
    ) async {
      final controller = await LocaleController.load(
        MemoryLocaleStore({'ui_locale': 'ur'}),
      );
      await tester.pumpWidget(DukaanProApp(localeController: controller));
      final context = tester.element(find.byType(Scaffold));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(context.l10n.languageMenuTooltip, 'زبان');
      expect(MaterialLocalizations.of(context).okButtonLabel, isNot('OK'));
      expect(Theme.of(context).textTheme.bodyMedium!.fontFamilyFallback, [
        'NotoNastaliqUrdu',
      ]);
      await controller.setUrduFont(UrduFont.naskh);
      await tester.pumpAndSettle(); // MaterialApp animates theme changes.
      expect(
        Theme.of(
          tester.element(find.byType(Scaffold)),
        ).textTheme.bodyMedium!.fontFamilyFallback,
        ['NotoNaskhArabic'],
      );
    });

    testWidgets('phone size: the switcher menu works in both languages', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryLocaleStore();
      final controller = LocaleController(store: store);
      await tester.pumpWidget(
        LocalizedMaterialApp(
          controller: controller,
          home: Scaffold(appBar: AppBar(actions: const [LanguageSwitcher()])),
        ),
      );
      final scaffold = tester.element(find.byType(Scaffold));
      await _choose(tester, 'language-ur');
      expect(
        Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.rtl,
      );
      // Same element: the screen was not rebuilt from scratch.
      expect(tester.element(find.byType(Scaffold)), same(scaffold));
      expect(store.values['ui_locale'], 'ur');
      // The Urdu font choice appears only in Urdu.
      await tester.tap(_switcher);
      await tester.pumpAndSettle();
      expect(find.text('نستعلیق'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('urdu-font-naskh')));
      await tester.pumpAndSettle();
      expect(controller.urduFont, UrduFont.naskh);
      await _choose(tester, 'language-en');
      expect(
        Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('POS keeps the cart and the barcode scanner across a switch', () {
    for (final size in const [Size(1340, 800), Size(1024, 600)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final db = AppDatabase(NativeDatabase.memory());
        final store = MemoryLocaleStore();
        final controller = LocaleController(store: store);
        await tester.pumpWidget(
          LocalizedMaterialApp(controller: controller, home: _pos(db)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final state = tester.state(find.byType(PosWorkspace));

        await _scan(tester, '8964000000017');
        expect(
          find.descendant(of: _bill, matching: find.text('Surf')),
          findsOneWidget,
        );

        await _choose(tester, 'language-ur');
        expect(Directionality.of(tester.element(_bill)), TextDirection.rtl);
        expect(tester.state(find.byType(PosWorkspace)), same(state));
        expect(
          find.descendant(of: _bill, matching: find.text(isolateAuto('Surf'))),
          findsOneWidget,
        );
        // RTL layout: the sidebar is on the right of the bill panel.
        expect(
          tester.getCenter(find.byKey(const ValueKey('cashier-sidebar'))).dx,
          greaterThan(tester.getCenter(_bill).dx),
        );
        // A hardware scan still adds the product while the UI is Urdu.
        await _scan(tester, '8964000000024');
        expect(
          find.descendant(of: _bill, matching: find.text(isolateAuto('Tea'))),
          findsOneWidget,
        );
        expect(store.values['ui_locale'], 'ur');

        await _choose(tester, 'language-en');
        expect(Directionality.of(tester.element(_bill)), TextDirection.ltr);
        expect(tester.state(find.byType(PosWorkspace)), same(state));
        for (final name in ['Surf', 'Tea']) {
          expect(
            find.descendant(of: _bill, matching: find.text(name)),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(db.close);
      });
    }

    testWidgets('600x960 (bill in a sheet)', (tester) async {
      tester.view.physicalSize = const Size(600, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      final controller = LocaleController(store: MemoryLocaleStore());
      await tester.pumpWidget(
        LocalizedMaterialApp(controller: controller, home: _pos(db)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final state = tester.state(find.byType(PosWorkspace));
      await _scan(tester, '8964000000017');
      await _choose(tester, 'language-ur');
      await _scan(tester, '8964000000024');
      expect(tester.state(find.byType(PosWorkspace)), same(state));
      await tester.tap(find.byKey(const ValueKey('open-cart-button')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('pay-button'));
      expect(Directionality.of(tester.element(sheet)), TextDirection.rtl);
      expect(find.text(isolateAuto('Surf')), findsWidgets);
      expect(find.text(isolateAuto('Tea')), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(db.close);
    });

    testWidgets('without the app shell the switcher renders nothing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1340, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(MaterialApp(home: _pos(db)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_switcher, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(db.close);
    });
  });
}

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.tap(_switcher);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _scan(WidgetTester tester, String barcode) async {
  for (final digit in barcode.split('')) {
    await tester.sendKeyEvent(
      LogicalKeyboardKey(0x30 + int.parse(digit)),
      character: digit,
    );
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

PosWorkspace _pos(AppDatabase db) => PosWorkspace(
  shopName: 'ALI Shop',
  cashierName: 'ahmed1',
  initialCatalog: const PosCatalogSnapshot(
    products: [_surf, _tea],
    categories: [PosCategory(id: 'household', name: 'Household')],
    customers: [],
  ),
  committer: _Committer(),
  salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
  offline: false,
  initialHasPendingSync: false,
  onLogout: () async {},
);

final class _ThrowingStore implements LocalePreferenceStore {
  @override
  Future<String?> read(String key) => throw StateError('unreadable');
  @override
  Future<void> write(String key, String value) => throw StateError('full');
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
