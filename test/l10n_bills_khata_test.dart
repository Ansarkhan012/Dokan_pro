// Stage 2B Batch 4: Bills, returns, voids and the Udhaar Khata in Urdu.
// Real sales, a partial return, a void and an Udhaar repayment go through
// the unchanged services on a local Drift database; the Bills list, bill
// detail and Khata then render in Urdu with exactly the amounts the English
// screens show (real Roboto + Noto Nastaliq/Naskh metrics, 360x800,
// 1024x600, 1340x800, text scale 1.0 / 1.3). Stock and balances are the
// same exact paisa values whatever the language.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/core/l10n/messages.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/customer_khata_view.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/customers/drift_customer_repository.dart';
import 'package:dukaan_pro/features/customers/local_customer_payment_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_r1/support/pos_fixture.dart';
import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));
const _customerName = 'Ahmed احمد';

void main() {
  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('status and message mapping', () {
    test('stored bill statuses: English unchanged, Urdu translated', () {
      const statuses = {
        'Completed': 'مکمل',
        'Voided': 'منسوخ',
        'Fully Returned': 'مکمل واپس',
        'Partially Returned': 'جزوی واپس',
      };
      for (final MapEntry(key: status, value: urdu) in statuses.entries) {
        expect(localizedSaleStatus(_en, status), status);
        expect(localizedSaleStatus(_ur, status), urdu);
      }
      expect(localizedSaleStatus(_ur, 'Something new'), 'Something new');
      expect(_en.paymentStored('cash', 'cash'), 'cash');
      expect(_ur.paymentStored('cash', 'cash'), 'کیش');
    });

    test('Khata and customer messages', () {
      for (final message in [
        'Enter an amount greater than zero.',
        'Name and a valid credit limit are required.',
        'Customers could not be refreshed. Showing available offline data.',
        'Sales could not be loaded. Please try again.',
        'Payment cannot exceed Rs 1250.00.',
      ]) {
        expect(localizedMessage(_en, message), message);
        expect(localizedMessage(_ur, message), isNot(message));
      }
      expect(
        localizedMessage(_ur, 'Payment cannot exceed Rs 1250.00.'),
        _ur.khataErrExceeds(isolateLtr('Rs 1250.00')),
      );
    });
  });

  group('financial results are the same in both languages', () {
    test('return, void and repayment through the unchanged services', () async {
      final f = await _Fixture.open();
      // 4 sold (2 + 1 voided + 1 Udhaar), 1 returned, 1 restored by the void.
      expect(await f.h.stock(cokeId), openingStock - 4000 + 1000 + 1000);
      // Udhaar: 1 coke on credit (180.00) minus 50.00 paid back.
      expect(await f.balance(), cokePrice - 5000);
      final sales = await (f.h.db.select(
        f.h.db.sales,
      )..orderBy([(s) => OrderingTerm.asc(s.createdAt)])).get();
      expect(sales.map((s) => s.grandTotal), [
        cokePrice * 2,
        cokePrice,
        cokePrice,
      ]);
      await f.h.db.close();
    });
  });

  group('Bills in Urdu (real fonts)', () {
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.nastaliq, 1.0),
      (Size(360, 800), UrduFont.naskh, 1.3),
      (Size(1024, 600), UrduFont.naskh, 1.0),
      (Size(1340, 800), UrduFont.nastaliq, 1.3),
      (Size(1340, 800), UrduFont.naskh, 1.0),
    ]) {
      testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} ${font.name} x$scale',
        (tester) async {
          final f = await _Fixture.open();
          final c = LocaleController(
            initialLocale: LocaleController.urdu,
            initialUrduFont: font,
          );
          await _pumpBills(tester, f, size, scale, c);
          expect(find.text(_ur.billsTodaySales), findsOneWidget);
          expect(find.text(_ur.billsCountMany('3')), findsOneWidget);
          // On a phone the oldest bill starts below the fold.
          await tester.scrollUntilVisible(
            find.text('جزوی واپس'),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('جزوی واپس'), findsOneWidget);
          expect(find.text('منسوخ'), findsOneWidget);
          expect(find.text('مکمل'), findsOneWidget);
          expect(find.textContaining(isolateAuto(_customerName)), findsWidgets);
          final urduAmounts = _amounts(tester);
          expect(tester.takeException(), isNull);

          // The partially returned bill in detail.
          await tester.ensureVisible(find.text('جزوی واپس'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('جزوی واپس'));
          await tester.pumpAndSettle();
          final wide = size.width >= 1000;
          // A phone's detail dialog builds its rows lazily: scroll to them.
          await _scrollDialogTo(tester, find.textContaining('واپسی: '));
          expect(find.text(_ur.billNet), findsOneWidget);
          expect(find.text(_ur.billPaidBy(_ur.paymentCash)), findsOneWidget);
          expect(find.textContaining('واپسی: '), findsOneWidget);
          expect(
            find.textContaining(isolateAuto('ٹوٹی ہوئی بوتل')),
            findsOneWidget,
          );
          expect(find.text(_ur.billReturnItems), findsOneWidget);
          expect(tester.takeException(), isNull);
          final detailUrdu = wide ? _amounts(tester) : const <String>[];
          await tester.tap(find.text(_ur.commonClose));
          await tester.pumpAndSettle();

          // Switching language keeps the screen; every amount is identical.
          await c.setLocale(LocaleController.english);
          await tester.pumpAndSettle();
          expect(find.text('Partially Returned'), findsOneWidget);
          expect(find.text('Voided'), findsOneWidget);
          if (size.width >= 1000) expect(_amounts(tester), urduAmounts);
          await tester.ensureVisible(find.text('Partially Returned'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Partially Returned'));
          await tester.pumpAndSettle();
          await _scrollDialogTo(tester, find.textContaining('Return: '));
          expect(find.text('Net'), findsOneWidget);
          expect(find.textContaining('Return: '), findsOneWidget);
          // Same rows built at tablet width: amounts must match exactly.
          if (wide) expect(_amounts(tester), detailUrdu);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          await _dispose(tester, f);
        },
      );
    }

    testWidgets('English bills on a phone at text scale 1.3: no overflow', (
      tester,
    ) async {
      final f = await _Fixture.open();
      await _pumpBills(
        tester,
        f,
        const Size(360, 800),
        1.3,
        LocaleController(),
      );
      await tester.scrollUntilVisible(
        find.text('Partially Returned'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await _dispose(tester, f);
    });

    testWidgets('English bills text is unchanged', (tester) async {
      final f = await _Fixture.open();
      await _pumpBills(
        tester,
        f,
        const Size(1340, 800),
        1.0,
        LocaleController(),
      );
      expect(find.text("Today's sales"), findsOneWidget);
      expect(find.text('3 bills'), findsOneWidget);
      expect(find.text('All payments'), findsOneWidget);
      expect(find.text('Waiting to sync'), findsNWidgets(3));
      await tester.tap(find.text('Partially Returned'));
      await tester.pumpAndSettle();
      expect(find.text('Paid by Cash'), findsOneWidget);
      expect(
        find.textContaining('• ٹوٹی ہوئی بوتل • Rs 180.00'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await _dispose(tester, f);
    });
  });

  group('Khata in Urdu (real fonts)', () {
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.nastaliq, 1.3),
      (Size(1024, 600), UrduFont.naskh, 1.0),
      (Size(1340, 800), UrduFont.nastaliq, 1.0),
    ]) {
      testWidgets(
        'repayment ${size.width.toInt()}x${size.height.toInt()} ${font.name} x$scale',
        (tester) async {
          final f = await _Fixture.open(repay: false);
          final c = LocaleController(
            initialLocale: LocaleController.urdu,
            initialUrduFont: font,
          );
          await _pumpKhata(tester, f, size, scale, c);
          expect(find.text(isolateAuto(_customerName)), findsOneWidget);
          expect(
            find.text(_ur.khataDue(isolateLtr('Rs 180.00'))),
            findsOneWidget,
          );
          await tester.tap(find.text(isolateAuto(_customerName)));
          await tester.pumpAndSettle();
          expect(find.text(_ur.khataStatement), findsOneWidget);
          expect(find.text(_ur.khataCreditLimit), findsOneWidget);
          expect(find.textContaining('${_ur.ledgerSale} • '), findsOneWidget);

          await tester.tap(find.text(_ur.khataReceivePayment));
          await tester.pumpAndSettle();
          final amount = find.byType(TextField).first;
          // Too much, typed with Urdu digits: refused in Urdu, the limit kept.
          await tester.enterText(amount, '۵۰۰');
          await tester.tap(find.text(_ur.khataRecordPayment));
          await tester.pumpAndSettle();
          expect(
            find.text(_ur.khataErrExceeds(isolateLtr('Rs 180.00'))),
            findsOneWidget,
          );
          // A switch mid-dialog keeps the typed amount and re-translates.
          await c.setLocale(LocaleController.english);
          await tester.pumpAndSettle();
          expect(find.text('Payment cannot exceed Rs 180.00.'), findsOneWidget);
          expect(tester.widget<TextField>(amount).controller!.text, '500');
          await c.setLocale(LocaleController.urdu);
          await tester.pumpAndSettle();
          await tester.enterText(amount, '۵۰');
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(_ur.khataRecordPayment));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          expect(await f.balance(), cokePrice - 5000);
          // Regression: the saved payment is reported as saved (it used to say
          // "could not be recorded" in debug builds).
          expect(find.text(_ur.khataPaymentSaved), findsOneWidget);
          expect(find.text(_ur.khataPaymentFailed), findsNothing);
          final paymentLine = find.textContaining('${_ur.ledgerPayment} • کیش');
          if (paymentLine.evaluate().isEmpty) {
            // A phone's statement builds lines lazily: bring the newest in.
            await tester.drag(
              find.byType(ListView).last,
              const Offset(0, -600),
            );
            await tester.pumpAndSettle();
          }
          expect(paymentLine, findsOneWidget);
          expect(
            find.text(_ur.khataRunningBalance(isolateLtr('Rs 130.00'))),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await _dispose(tester, f);
        },
      );
    }

    testWidgets('Khata search filters the list (both languages)', (
      tester,
    ) async {
      final f = await _Fixture.open(repay: false);
      await f.h.db
          .into(f.h.db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'bilal',
              shopId: shopId,
              name: 'Bilal بلال',
              phone: const Value('03001234567'),
              createdAt: DateTime.utc(2026, 9, 1),
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          );
      final c = LocaleController(initialLocale: LocaleController.urdu);
      await _pumpKhata(tester, f, const Size(360, 800), 1.0, c);
      expect(find.text(isolateAuto('Bilal بلال')), findsOneWidget);
      expect(find.text(isolateLtr('03001234567')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'احمد');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text(isolateAuto(_customerName)), findsOneWidget);
      expect(find.text(isolateAuto('Bilal بلال')), findsNothing);
      await c.setLocale(LocaleController.english);
      await tester.pumpAndSettle();
      expect(find.text(_customerName), findsOneWidget);
      expect(find.text('Bilal بلال'), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester, f);
    });

    testWidgets('English repayment reports success', (tester) async {
      final f = await _Fixture.open(repay: false);
      await _pumpKhata(
        tester,
        f,
        const Size(1340, 800),
        1.0,
        LocaleController(),
      );
      await tester.tap(find.text(_customerName));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receive Payment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(await f.balance(), cokePrice - 5000);
      expect(
        find.text('Payment saved locally and queued for sync.'),
        findsOneWidget,
      );
      expect(
        find.text('Payment could not be recorded. Nothing was changed.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await _dispose(tester, f);
    });

    testWidgets('English Khata text is unchanged', (tester) async {
      final f = await _Fixture.open(repay: false);
      await _pumpKhata(
        tester,
        f,
        const Size(1340, 800),
        1.0,
        LocaleController(),
      );
      expect(find.text('Rs 180.00 due'), findsOneWidget);
      await tester.tap(find.text(_customerName));
      await tester.pumpAndSettle();
      expect(find.text('Credit limit'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.textContaining('Sale • '), findsOneWidget);
      await _dispose(tester, f);
    });
  });
}

/// Three bills today: 2 Coke cash with 1 returned (partially returned),
/// 1 Coke cash voided, 1 Coke on Udhaar to Ahmed (optionally 50.00 repaid).
final class _Fixture {
  _Fixture(this.h);
  final PosHarness h;

  static Future<_Fixture> open({bool repay = true}) async {
    final h = await PosHarness.open();
    final db = h.db;
    await (db.update(db.customers)..where((t) => t.id.equals(customerId)))
        .write(const CustomersCompanion(name: Value(_customerName)));
    Future<String> sell(int units, PaymentMethod method) async =>
        (await LocalSaleService(db, const UuidV7Generator()).createSale(
          SaleDraft(
            shopId: shopId,
            cashierId: ownerId,
            deviceId: deviceId,
            customerId: method == PaymentMethod.credit ? customerId : null,
            lines: [SaleLineDraft(productId: cokeId, quantity: units * 1000)],
            payments: [
              SalePaymentDraft(method: method, amountMinor: cokePrice * units),
            ],
          ),
        )).saleId;
    final returned = await sell(2, PaymentMethod.cash);
    final voided = await sell(1, PaymentMethod.cash);
    await sell(1, PaymentMethod.credit);
    final item = await (db.select(
      db.saleItems,
    )..where((t) => t.saleId.equals(returned))).getSingle();
    await LocalSaleReturnService(db, const UuidV7Generator()).create(
      SaleReturnDraft(
        shopId: shopId,
        originalSaleId: returned,
        ownerId: ownerId,
        deviceId: deviceId,
        refundMethod: PaymentMethod.cash,
        reason: 'ٹوٹی ہوئی بوتل',
        lines: [
          SaleReturnLineDraft(originalSaleItemId: item.id, quantity: 1000),
        ],
      ),
    );
    await LocalSaleVoidService(db, const UuidV7Generator()).voidSale(
      shopId: shopId,
      saleId: voided,
      ownerId: ownerId,
      deviceId: deviceId,
      reason: 'Wrong bill',
    );
    final f = _Fixture(h);
    if (repay) await f.pay(5000);
    return f;
  }

  Future<void> pay(int amountMinor) =>
      LocalCustomerPaymentService(h.db, const UuidV7Generator()).receive(
        shopId: shopId,
        customerId: customerId,
        actorId: ownerId,
        deviceId: deviceId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
      );

  Future<int> balance() async => (await DriftCustomerRepository(
    h.db,
    shopId: shopId,
  ).search('')).singleWhere((c) => c.id == customerId).balanceMinor;
}

final class _Actions implements CustomerKhataActions {
  _Actions(this.f);
  final _Fixture f;
  @override
  Future<List<CustomerAccount>> searchCustomers(String query) =>
      DriftCustomerRepository(f.h.db, shopId: shopId).search(query);
  @override
  Future<List<CustomerLedgerLine>> statement(String id) =>
      DriftCustomerRepository(f.h.db, shopId: shopId).statement(id);
  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) => f.pay(amountMinor);
}

Future<void> _setUp(WidgetTester tester, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

Future<void> _pumpBills(
  WidgetTester tester,
  _Fixture f,
  Size size,
  double scale,
  LocaleController c,
) async {
  await _setUp(tester, size, scale);
  await tester.pumpWidget(
    LocalizedMaterialApp(
      controller: c,
      home: Scaffold(
        body: SalesHistoryView(
          repository: DriftSalesHistoryRepository(f.h.db, shopId: shopId),
          shopName: 'Ali Shop',
          onReturn: (_) async {},
          onVoid: (_) async {},
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpKhata(
  WidgetTester tester,
  _Fixture f,
  Size size,
  double scale,
  LocaleController c,
) async {
  await _setUp(tester, size, scale);
  await tester.pumpWidget(
    LocalizedMaterialApp(
      controller: c,
      home: Scaffold(body: CustomerKhataView(actions: _Actions(f))),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _scrollDialogTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      80,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );

/// Every `Rs …` amount on screen, isolates removed, sorted: the same list in
/// Urdu and English means no amount changed with the language.
List<String> _amounts(WidgetTester tester) {
  final isolates = RegExp(
    '[${leftToRightIsolate + firstStrongIsolate + popDirectionalIsolate}]',
  );
  return [
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      for (final m in RegExp(
        r'[-+]?Rs [0-9]+\.[0-9]{2}',
      ).allMatches((text.data ?? '').replaceAll(isolates, '')))
        m[0]!,
  ]..sort();
}

Future<void> _dispose(WidgetTester tester, _Fixture f) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  await f.h.db.close();
}
