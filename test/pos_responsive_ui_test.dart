import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/pos/product_thumbnail.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'thumbnail supports local image, missing image and failed fallback',
    (tester) async {
      final file = File('${Directory.systemTemp.path}/dukaan-product-test.png');
      file.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ProductThumbnail(imagePath: file.path),
                const ProductThumbnail(),
                const ProductThumbnail(imagePath: 'missing-local-image.png'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('product-image')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('product-image-placeholder')),
        findsNWidgets(2),
      );
    },
  );

  testWidgets('long product name keeps thumbnail, price, stock and Add visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 220,
          height: 150,
          child: PosProductCard(
            product: _product(
              name:
                  'Very Long Pakistani Grocery Product Name That Must Truncate Safely',
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Rs 570.00'), findsOneWidget);
    expect(find.textContaining('Stock 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1024, 600),
    Size(1280, 800),
    Size(1366, 768),
    Size(1920, 1080),
  ]) {
    testWidgets(
      'POS remains usable without overflow at ${size.width}x${size.height}',
      (tester) async {
        final db = await _pumpPos(tester, size);
        expect(find.text('New Sale'), findsOneWidget);
        expect(find.text('Search product or scan barcode'), findsOneWidget);
        expect(find.byKey(const ValueKey('pay-button')), findsOneWidget);
        expect(find.text('Add'), findsWidgets);
        expect(find.byKey(const ValueKey('cashier-sidebar')), findsOneWidget);
        for (final ownerOnly in [
          'Purchases',
          'Expenses',
          'Reports',
          'Settings',
          'Cashier Management',
        ]) {
          expect(find.text(ownerOnly), findsNothing);
        }
        expect(tester.takeException(), isNull);
        if (size == const Size(1024, 600) &&
            const bool.fromEnvironment('CAPTURE_POS')) {
          await tester.tap(find.text('Add').at(0));
          await tester.tap(find.text('Add').at(2));
          await tester.tap(find.text('Add').at(2));
          await tester.tap(find.text('Add').at(4));
          await tester.pump();
          await expectLater(
            find.byType(PosWorkspace),
            matchesGoldenFile('../build/design_qa/pos-1024x600.png'),
          );
        }
        await _disposePos(tester, db);
      },
    );
  }

  testWidgets('narrow layout exposes accessible current bill sheet', (
    tester,
  ) async {
    final db = await _pumpPos(tester, const Size(600, 960));
    expect(find.byKey(const ValueKey('open-cart-button')), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.tap(find.byKey(const ValueKey('open-cart-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay-button')), findsOneWidget);
    expect(find.text('Current Bill'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposePos(tester, db);
  });
}

Future<AppDatabase> _pumpPos(WidgetTester tester, Size size) async {
  const capture = bool.fromEnvironment('CAPTURE_POS');
  if (capture) {
    final bytes = File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytesSync();
    final loader = FontLoader('Segoe UI')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await tester.runAsync(loader.load);
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase(NativeDatabase.memory());
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff176b52),
        fontFamily: capture ? 'Segoe UI' : null,
      ),
      home: PosWorkspace(
        shopName: 'ALI Shop',
        cashierName: 'ahmed1',
        initialCatalog: PosCatalogSnapshot(
          products: capture
              ? [
                  _product(),
                  _product(name: 'Sugar 1kg', id: 'sugar', price: 16500),
                  _product(name: 'Milk 1L', id: 'milk', price: 21000),
                  _product(name: 'Tea 475g', id: 'tea', price: 89000),
                  _product(name: 'Biscuits', id: 'biscuits', price: 8000),
                  _product(name: 'Rice 1kg', id: 'rice', price: 32000),
                ]
              : [_product()],
          categories: const [
            PosCategory(id: 'grocery', name: 'Grocery'),
            PosCategory(id: 'daal', name: 'Daal'),
            PosCategory(id: 'drinks', name: 'Drinks'),
            PosCategory(id: 'snacks', name: 'Snacks'),
          ],
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

PosProduct _product({
  String name = 'DAAL',
  String id = 'daal',
  int price = 57000,
}) => PosProduct(
  id: id,
  name: name,
  salePriceMinor: price,
  stockQuantity: 9000,
  stockTrackingEnabled: true,
  categoryId: 'grocery',
);

final class _Committer implements PosSaleCommitter {
  @override
  bool get lastSyncSucceeded => false;
  @override
  Future<CreatedSale> complete(PosCart cart, PosPaymentPlan payment) =>
      throw UnimplementedError();
  @override
  Future<PosCatalogSnapshot> reloadCatalog() => throw UnimplementedError();
  @override
  Future<bool> triggerSync() async => false;
  @override
  Stream<bool> watchHasPendingSync() => const Stream.empty();
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
