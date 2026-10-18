// Stage 2B Batch 5: owner screens (Purchases, Expenses, Dashboard, Settings)
// in Urdu, and the async setState regressions. Each screen runs as in the
// app: its own file-backed Drift database (in a temp folder) and a Supabase
// client whose network calls fail locally, with a fake local owner session.
// Successful saves must report success (never a false failure that invites a
// duplicate entry), lists refresh, totals equal English, and nothing
// overflows (real Roboto + Noto Nastaliq/Naskh, 360x800 / 1024x600 /
// 1340x800, text scale 1.0 / 1.3).
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/core/l10n/messages.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/expenses/expense_category_l10n.dart';
import 'package:dukaan_pro/features/expenses/expense_management_native.dart';
import 'package:dukaan_pro/features/purchases/purchase_management_native.dart';
import 'package:dukaan_pro/features/reports/owner_dashboard_native.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/settings/owner_settings_screen.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));

/// A real UUID-shaped shop id: default expense category ids derive from it.
const _shop = '11111111-2222-3333-4444-555555555555';
const _owner = 'owner-1';
final _t = DateTime.utc(2026, 9, 1);

void main() {
  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('default expense categories by stable id', () {
    test('ids match the server formula (reference from PostgreSQL)', () {
      // select md5('<shop>:expense:'||lower('Food/Tea'))::uuid
      expect(
        defaultExpenseCategoryId(_shop, 'Food/Tea'),
        'f5a7e8f3-eea5-1891-d3e1-1ef55336a038',
      );
    });

    test('English unchanged; Urdu by id only; shop categories as entered', () {
      for (final (name, urdu) in [
        ('Rent', 'کرایہ'),
        ('Electricity', 'بجلی'),
        ('Food/Tea', 'کھانا / چائے'),
        ('Miscellaneous', 'متفرق'),
      ]) {
        final id = defaultExpenseCategoryId(_shop, name);
        expect(
          localizedExpenseCategory(_en, shopId: _shop, id: id, name: name),
          name,
        );
        expect(
          localizedExpenseCategory(_ur, shopId: _shop, id: id, name: name),
          urdu,
        );
      }
      // Same name, other id (a shop's own "Rent"): never translated.
      expect(
        localizedExpenseCategory(_ur, shopId: _shop, id: 'x', name: 'Rent'),
        'Rent',
      );
      // Another shop's default id is not this shop's default.
      expect(
        localizedExpenseCategory(
          _ur,
          shopId: _shop,
          id: defaultExpenseCategoryId('other-shop', 'Rent'),
          name: 'Rent',
        ),
        'Rent',
      );
    });

    test('stored messages: English unchanged, Urdu translated', () {
      for (final m in [
        'Could not save the purchase. Please try again.',
        'Could not save the expense. Please try again.',
        'Showing cached settings.',
        'Settings are unavailable offline until the first sync.',
        'Enter a shop name and a non-negative stock threshold.',
        'Could not save settings. Check your connection.',
        'Enter the cashier name.',
        'PIN must contain 4 to 8 digits.',
        'PINs do not match.',
      ]) {
        expect(localizedMessage(_en, m), m);
        expect(localizedMessage(_ur, m), isNot(m));
      }
    });
  });

  group('Purchases: saves report success, statements refresh', () {
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.nastaliq, 1.3),
      (Size(1024, 600), UrduFont.naskh, 1.0),
      (Size(1340, 800), UrduFont.nastaliq, 1.0),
    ]) {
      testWidgets('supplier payment ${_name(size)} ${font.name} x$scale', (
        tester,
      ) async {
        final env = await _Env.open(tester, size, scale, (db) async {
          await db
              .into(db.suppliers)
              .insert(
                SuppliersCompanion.insert(
                  id: 'sup',
                  shopId: _shop,
                  name: 'Karachi Traders کراچی',
                  createdAt: _t,
                  updatedAt: _t,
                ),
              );
          await db
              .into(db.supplierLedgerEntries)
              .insert(
                SupplierLedgerEntriesCompanion.insert(
                  id: 'l1',
                  shopId: _shop,
                  supplierId: 'sup',
                  type: SupplierLedgerType.purchase,
                  amount: 50000,
                  createdBy: _owner,
                  createdAt: _t,
                ),
              );
        });
        await env.pump(
          tester,
          PurchaseManagementScreen(
            client: env.client,
            shopId: _shop,
            deviceId: 'device',
            authorizer: const AllowFinancialMutations(),
          ),
          urdu: true,
          font: font,
          until: find.textContaining('Karachi'),
        );
        expect(
          find.text(_ur.suppliersPayable(isolateLtr('Rs 500.00'))),
          findsOneWidget,
        );
        await tester.tap(find.textContaining('Karachi'));
        await env.settle(tester);
        await tester.tap(find.text(_ur.khataRecordPayment));
        await tester.pumpAndSettle();
        expect(find.text(_ur.supplierPaymentTitle), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '۲۰۰');
        await tester.tap(find.text(_ur.supplierPaymentRecord));
        await env.settle(tester, until: find.text(_ur.ledgerPayment));
        // Regression: the statement refreshes and nothing throws.
        expect(find.text(_ur.supplierPaymentSaved), findsOneWidget);
        expect(find.text(_ur.supplierPaymentFailed), findsNothing);
        expect(find.text(_ur.ledgerPayment), findsOneWidget);
        expect(
          find.text('${isolateLtr('-Rs 200.00')} • ${isolateLtr('Rs 300.00')}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final payments = await env.rows(
          tester,
          "select amount from supplier_ledger_entries where type='paymentMade'",
        );
        expect(payments, [20000]); // exactly one payment
        await env.close(tester);
      });
    }

    testWidgets('refused supplier payment: failure shown, nothing recorded', (
      tester,
    ) async {
      final env = await _Env.open(tester, const Size(1340, 800), 1.0, (
        db,
      ) async {
        await db
            .into(db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                id: 'sup',
                shopId: _shop,
                name: 'Karachi Traders',
                createdAt: _t,
                updatedAt: _t,
              ),
            );
        await db
            .into(db.supplierLedgerEntries)
            .insert(
              SupplierLedgerEntriesCompanion.insert(
                id: 'l1',
                shopId: _shop,
                supplierId: 'sup',
                type: SupplierLedgerType.purchase,
                amount: 50000,
                createdBy: _owner,
                createdAt: _t,
              ),
            );
      });
      await env.pump(
        tester,
        PurchaseManagementScreen(
          client: env.client,
          shopId: _shop,
          deviceId: 'device',
          authorizer: const _Refuse(),
        ),
        urdu: false,
        until: find.textContaining('Karachi'),
      );
      await tester.tap(find.textContaining('Karachi'));
      await env.settle(tester);
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '200');
      await tester.tap(find.text('Record'));
      const failed =
          'Supplier payment could not be recorded. Nothing was changed.';
      await env.settle(tester, until: find.text(failed));
      expect(find.text(failed), findsOneWidget);
      expect(find.text('Supplier payment saved locally.'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        await env.rows(
          tester,
          "select amount from supplier_ledger_entries where type='paymentMade'",
        ),
        isEmpty,
      );
      await env.close(tester);
    });

    testWidgets(
      'new purchase: success shown, one purchase, form survives a switch',
      (tester) async {
        final env = await _Env.open(tester, const Size(1340, 800), 1.0, (
          db,
        ) async {
          await db
              .into(db.suppliers)
              .insert(
                SuppliersCompanion.insert(
                  id: 'sup',
                  shopId: _shop,
                  name: 'Karachi Traders',
                  createdAt: _t,
                  updatedAt: _t,
                ),
              );
          await db
              .into(db.shopProducts)
              .insert(
                ShopProductsCompanion.insert(
                  id: 'surf',
                  shopId: _shop,
                  customName: const Value('Surf'),
                  purchasePrice: 30000,
                  salePrice: 35000,
                  createdAt: _t,
                  updatedAt: _t,
                ),
              );
        });
        await env.pump(
          tester,
          PurchaseManagementScreen(
            client: env.client,
            shopId: _shop,
            deviceId: 'device',
            authorizer: const AllowFinancialMutations(),
          ),
          urdu: true,
          until: find.textContaining('Karachi'),
        );
        await tester.tap(find.text(_ur.purchasesTabPurchases));
        await env.settle(tester);
        await tester.tap(find.text(_ur.purchasesNew));
        await env.settle(tester, until: find.text(_ur.purchasesNewTitle));
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(isolateAuto('Karachi Traders')).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextField),
              )
              .first,
          '۲',
        );
        await tester.tap(find.text(_ur.posAdd));
        await tester.pumpAndSettle();
        expect(
          find.text(
            _ur.purchaseLineQtyCost(isolateLtr('2'), isolateLtr('Rs 300.00')),
          ),
          findsOneWidget,
        );
        // Switching language keeps the unsaved purchase.
        await env.controller.setLocale(LocaleController.english);
        await tester.pumpAndSettle();
        expect(find.text('Qty 2 @ Rs 300.00'), findsOneWidget);
        expect(find.text('Total Rs 600.00'), findsOneWidget);
        await env.controller.setLocale(LocaleController.urdu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_ur.purchaseSave));
        await env.settle(tester, until: find.text(_ur.purchasesSaved));
        // Regression: success, never "could not save".
        expect(find.text(_ur.purchasesSaved), findsOneWidget);
        expect(find.text(_ur.purchasesErrSaveFailed), findsNothing);
        expect(tester.takeException(), isNull);
        expect(await env.rows(tester, 'select total from purchases'), [60000]);
        await env.close(tester);
      },
    );
  });

  group('Expenses: categories by id, success shown, one expense', () {
    for (final (size, font, scale, urdu) in const [
      (Size(360, 800), UrduFont.naskh, 1.3, true),
      (Size(1340, 800), UrduFont.nastaliq, 1.0, true),
      (Size(1340, 800), UrduFont.nastaliq, 1.0, false),
    ]) {
      testWidgets(
        '${urdu ? 'Urdu' : 'English'} ${_name(size)} ${font.name} x$scale',
        (tester) async {
          final rent = defaultExpenseCategoryId(_shop, 'Rent');
          final env = await _Env.open(tester, size, scale, (db) async {
            for (final (id, name) in [
              (rent, 'Rent'),
              ('own-cat', 'Chai Pani'),
            ]) {
              await db
                  .into(db.expenseCategories)
                  .insert(
                    ExpenseCategoriesCompanion.insert(
                      id: id,
                      shopId: _shop,
                      name: name,
                      createdAt: _t,
                      updatedAt: _t,
                    ),
                  );
            }
          });
          final l10n = urdu ? _ur : _en;
          await env.pump(
            tester,
            ExpenseManagementScreen(
              client: env.client,
              shopId: _shop,
              deviceId: 'device',
              authorizer: const AllowFinancialMutations(),
            ),
            urdu: urdu,
            font: font,
            until: find.text(l10n.expensesAdd),
          );
          await tester.tap(find.text(l10n.expensesAdd));
          await env.settle(tester);
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byWidgetPredicate(
                (w) => w is DropdownButtonFormField,
              ),
            ),
          );
          await env.settle(tester);
          final rentLabel = urdu ? isolateAuto('کرایہ') : 'Rent';
          expect(
            find.text(urdu ? isolateAuto('Chai Pani') : 'Chai Pani'),
            findsWidgets,
          );
          await tester.tap(find.text(rentLabel).last);
          await env.settle(tester);
          final fields = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          await tester.enterText(fields.at(0), 'دکان کا کرایہ');
          await tester.enterText(fields.at(1), urdu ? '۲۵۰۰۰' : '25000');
          await tester.tap(find.text(l10n.commonSave));
          await env.settle(tester, until: find.text(l10n.expensesSaved));
          expect(find.text(l10n.expensesSaved), findsOneWidget);
          expect(find.text(l10n.expensesErrSaveFailed), findsNothing);
          expect(tester.takeException(), isNull);
          expect(await env.rows(tester, 'select amount from expenses'), [
            2500000,
          ]);
          expect(await env.rows(tester, 'select category_id from expenses'), [
            rent,
          ]);
          await env.close(tester);
        },
      );
    }
  });

  group('Owner dashboard in Urdu', () {
    Finder cards() => find.byType(GridView);
    Finder chart() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_Bars',
    );
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.nastaliq, 1.3),
      (Size(1024, 600), UrduFont.naskh, 1.0),
      (Size(1340, 800), UrduFont.nastaliq, 1.0),
    ]) {
      testWidgets(
        '${_name(size)} ${font.name} x$scale: same totals as English',
        (tester) async {
          final env = await _Env.open(tester, size, scale, _seedSales);
          await env.pump(
            tester,
            OwnerDashboardScreen(
              client: env.client,
              shopId: _shop,
              shopName: 'Ali Shop',
            ),
            urdu: true,
            font: font,
            until: find.text(_ur.dashNetSalesCard),
          );
          expect(find.text(_ur.reportPreset('today', 'today')), findsOneWidget);
          expect(find.text(_ur.dashGrossProfit), findsOneWidget);
          // Regression: summary cards never overflow (they scale down).
          expect(tester.takeException(), isNull);
          final urduCards = _amounts(tester, within: cards());
          expect(urduCards, contains('Rs 540.00')); // 3 Coke: net sales
          // The chart stays left to right inside the Urdu screen.
          await tester.scrollUntilVisible(
            chart(),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(Directionality.of(tester.element(chart())), TextDirection.ltr);
          expect(find.text(_ur.dashSalesVsPurchases), findsOneWidget);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 5000),
          );
          await tester.pumpAndSettle();
          await env.controller.setLocale(LocaleController.english);
          await tester.pumpAndSettle();
          expect(find.text('Net Sales'), findsOneWidget);
          expect(find.text('today'), findsOneWidget);
          expect(_amounts(tester, within: cards()), urduCards);
          expect(tester.takeException(), isNull);
          await env.close(tester);
        },
      );
    }

    testWidgets('English on a phone at text scale 1.3: cards do not overflow', (
      tester,
    ) async {
      final env = await _Env.open(
        tester,
        const Size(360, 800),
        1.3,
        _seedSales,
      );
      await env.pump(
        tester,
        OwnerDashboardScreen(
          client: env.client,
          shopId: _shop,
          shopName: 'Ali Shop',
        ),
        urdu: false,
        until: find.text('Net Sales'),
      );
      expect(find.text('Customer Udhaar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await env.close(tester);
    });
  });

  group('Settings: language entry keeps the form', () {
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.naskh, 1.3),
      (Size(1340, 800), UrduFont.nastaliq, 1.0),
    ]) {
      testWidgets('${_name(size)} ${font.name} x$scale', (tester) async {
        final env = await _Env.open(tester, size, scale, (_) async {});
        final language = find.byKey(const ValueKey('settings-language'));
        await env.pump(
          tester,
          OwnerSettingsScreen(
            client: env.client,
            shopId: _shop,
            deviceId: 'device',
          ),
          urdu: false,
          font: font,
          until: find.text('Showing cached settings.'),
        );
        expect(find.text('Showing cached settings.'), findsOneWidget);
        // On a phone at a large text size the field starts below the fold.
        Finder shopName(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(TextField),
        );
        await tester.scrollUntilVisible(
          find.text('Shop name'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(shopName('Shop name'), 'Ali General Store علی');
        // The language section is above the shop details: scroll back up.
        await tester.scrollUntilVisible(
          language,
          -150,
          scrollable: find.byType(Scrollable).first,
        );
        final urduSegment = find.descendant(
          of: language,
          matching: find.text('اردو'),
        );
        await tester.ensureVisible(urduSegment);
        await tester.pumpAndSettle();
        await tester.tap(urduSegment);
        await tester.pumpAndSettle();
        expect(env.controller.isUrdu, isTrue);
        // The Urdu font choice appears with Urdu, right under the language.
        expect(
          find.byKey(const ValueKey('settings-urdu-font'), skipOffstage: false),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        // Back at the top: Urdu labels, the typed name kept.
        await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
        await tester.pumpAndSettle();
        expect(find.text(_ur.settingsShowingCached), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text(_ur.settingsShopName),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widget<TextField>(shopName(_ur.settingsShopName))
              .controller!
              .text,
          'Ali General Store علی',
        );
        expect(tester.takeException(), isNull);
        await env.close(tester);
      });
    }
  });
}

/// An authorizer that refuses every save (e.g. an expired subscription).
final class _Refuse implements FinancialMutationAuthorizer {
  const _Refuse();
  @override
  Future<EntitlementEvaluation> authorize({
    required String shopId,
    required String deviceId,
  }) =>
      Future.error(const SubscriptionMutationBlocked('Subscription expired.'));
}

String _name(Size size) => '${size.width.toInt()}x${size.height.toInt()}';

Future<void> _seedSales(AppDatabase db) async {
  await db
      .into(db.shopUsers)
      .insert(
        ShopUsersCompanion.insert(
          id: 'm',
          shopId: _shop,
          userId: _owner,
          role: ShopRole.owner,
          createdAt: _t,
        ),
      );
  await db
      .into(db.shopProducts)
      .insert(
        ShopProductsCompanion.insert(
          id: 'coke',
          shopId: _shop,
          customName: const Value('Coke'),
          // Not a stock test: untracked, so the seeded sales never depend on
          // stock (sales never oversell).
          stockTrackingEnabled: const Value(false),
          purchasePrice: 15000,
          salePrice: 18000,
          createdAt: _t,
          updatedAt: _t,
        ),
      );
  for (final (units, method) in [
    (2, PaymentMethod.cash),
    (1, PaymentMethod.digital),
  ]) {
    await LocalSaleService(db, const UuidV7Generator()).createSale(
      SaleDraft(
        shopId: _shop,
        cashierId: _owner,
        deviceId: 'device',
        lines: [SaleLineDraft(productId: 'coke', quantity: units * 1000)],
        payments: [
          SalePaymentDraft(method: method, amountMinor: units * 18000),
        ],
      ),
    );
  }
}

final class _Env {
  _Env(this.dir, this.client);
  final Directory dir;
  final SupabaseClient client;
  late LocaleController controller;

  File get file => File('${dir.path}/dukaan_pro.sqlite');

  static Future<_Env> open(
    WidgetTester tester,
    Size size,
    double scale,
    Future<void> Function(AppDatabase db) seed,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (scale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final dir = Directory.systemTemp.createTempSync('owner_screens_');
    // AppDatabase.open() resolves the app support folder: an isolated temp
    // folder, so the screen opens its own throwaway database file.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    final env = _Env(
      dir,
      SupabaseClient(
        'http://127.0.0.1:1',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    await tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase(env.file));
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(
              id: _shop,
              name: 'Ali Shop',
              phone: '',
              address: '',
              subscriptionPlan: SubscriptionPlan.trial,
              subscriptionStatus: SubscriptionStatus.trial,
              createdAt: _t,
              updatedAt: _t,
            ),
          );
      await db
          .into(db.devices)
          .insert(
            DevicesCompanion.insert(
              id: 'device',
              shopId: _shop,
              deviceName: 'd',
              deviceType: DeviceType.androidTablet,
              deviceIdentifier: 'd',
              createdAt: _t,
            ),
          );
      await seed(db);
      await db.close();
      // A local owner session (no network): the screens read its user id.
      String b64(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      final token =
          '${b64({'alg': 'HS256'})}.${b64({'sub': _owner, 'exp': 4102444800, 'role': 'authenticated'})}.x';
      await env.client.auth.setInitialSession(
        jsonEncode({
          'access_token': token,
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': 4102444800,
          'refresh_token': 'r',
          'user': {
            'id': _owner,
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-09-01T00:00:00Z',
          },
        }),
      );
    });
    return env;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    required bool urdu,
    UrduFont font = UrduFont.nastaliq,
    Finder? until,
  }) async {
    controller = LocaleController(
      initialLocale: urdu ? LocaleController.urdu : LocaleController.english,
      initialUrduFont: font,
    );
    await tester.pumpWidget(
      LocalizedMaterialApp(controller: controller, home: screen),
    );
    await settle(tester, until: until);
  }

  /// Lets the screen's background-isolate database and failing network calls
  /// finish (real time), pumping frames in between.
  Future<void> settle(WidgetTester tester, {Finder? until}) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (until != null && until.evaluate().isNotEmpty && i > 2) break;
      if (until == null && i > 6) break;
    }
    // Route transitions and FAB entrance animations run on the fake clock.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<List<Object?>> rows(WidgetTester tester, String sql) async =>
      (await tester.runAsync(() async {
        final db = AppDatabase(NativeDatabase(file));
        try {
          return [
            for (final r in await db.customSelect(sql).get())
              r.data.values.first,
          ];
        } finally {
          await db.close();
        }
      }))!;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold the database briefly; the OS cleans temp.
    }
  }
}

List<String> _amounts(WidgetTester tester, {Finder? within}) {
  final isolates = RegExp(
    '[$leftToRightIsolate$firstStrongIsolate$popDirectionalIsolate]',
  );
  return [
    for (final text in tester.widgetList<Text>(
      within == null
          ? find.byType(Text)
          : find.descendant(of: within, matching: find.byType(Text)),
    ))
      for (final m in RegExp(
        r'[-+]?Rs [0-9]+\.[0-9]{2}',
      ).allMatches((text.data ?? '').replaceAll(isolates, '')))
        m[0]!,
  ]..sort();
}
