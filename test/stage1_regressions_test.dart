// Stage 1 pilot-readiness regressions.
// INV-1: repeated lines of one product in one sale are checked against that
// product's stock in total, not line by line.
// RCP-1: the on-screen receipt shows each line's unit price and, only when
// the stored sale has one, its discount.
// IMG: an image chosen on this tablet shows after a restart from the local
// store; a product whose image exists only elsewhere (a Storage key or
// another device) and a corrupt file both fall back to the placeholder.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/core/images/product_image_store.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/pos/product_thumbnail.dart';
import 'package:dukaan_pro/features/receipts/receipt_view.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final _t = DateTime.utc(2026, 10, 11, 5);

/// Stock in thousandths: Surf 3 pieces, Atta 1 kg, Oil 1 L, Tapal 250 g x2
/// and Tapal 500 g x1 (independent pack variants of one family).
Future<AppDatabase> _shop({required bool allowNegativeStock}) async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.shops).insert(ShopsCompanion.insert(
    id: 'shop', name: 'Shop', phone: '', address: '',
    subscriptionPlan: SubscriptionPlan.trial,
    subscriptionStatus: SubscriptionStatus.trial,
    allowNegativeStock: Value(allowNegativeStock),
    createdAt: _t, updatedAt: _t,
  ));
  await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
    id: 'm', shopId: 'shop', userId: 'owner', role: ShopRole.owner, createdAt: _t,
  ));
  await db.into(db.devices).insert(DevicesCompanion.insert(
    id: 'device', shopId: 'shop', deviceName: 'd',
    deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: _t,
  ));
  await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
    id: 'surf', shopId: 'shop', customName: const Value('Surf'),
    purchasePrice: 30000, salePrice: 35000, createdAt: _t, updatedAt: _t,
  ));
  for (final (id, name, unit, price) in [
    ('atta', 'Atta', 'kg', 13000),
    ('oil', 'Oil', 'liter', 17500),
  ]) {
    await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
      id: id, shopId: 'shop', customName: Value(name), unit: Value(unit),
      sellMode: Value(SellMode.measured.name),
      purchasePrice: price - 1000, salePrice: price, createdAt: _t, updatedAt: _t,
    ));
  }
  for (final (id, label, price) in [
    ('tapal-250', '250 g', 41000),
    ('tapal-500', '500 g', 80000),
  ]) {
    await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
      id: id, shopId: 'shop', customName: const Value('Tapal Danedar'),
      packLabel: Value(label), familyId: const Value('family-tapal'),
      purchasePrice: price - 3000, salePrice: price, createdAt: _t, updatedAt: _t,
    ));
  }
  for (final (id, stock) in [
    ('surf', 3000),
    ('atta', 1000),
    ('oil', 1000),
    ('tapal-250', 2000),
    ('tapal-500', 1000),
  ]) {
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
      id: 'open-$id', shopId: 'shop', productId: id,
      type: InventoryMovementType.openingStock, quantity: stock,
      createdBy: 'owner', createdAt: _t,
    ));
  }
  return db;
}

/// Sells [lines] (product id, thousandths) for cash at the exact total.
Future<CreatedSale> _sell(AppDatabase db, List<(String, int)> lines) async {
  var total = 0;
  for (final (id, quantity) in lines) {
    final price = (await (db.select(db.shopProducts)
          ..where((t) => t.id.equals(id))).getSingle()).salePrice;
    total += (price * quantity + 500) ~/ 1000;
  }
  return LocalSaleService(db, const UuidV7Generator(), clock: () => _t)
      .createSale(SaleDraft(
    shopId: 'shop', cashierId: 'owner', deviceId: 'device',
    lines: [
      for (final (id, quantity) in lines)
        SaleLineDraft(productId: id, quantity: quantity),
    ],
    payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: total)],
  ));
}

Future<int> _stock(AppDatabase db, String id) async {
  final rows = await (db.select(db.inventoryMovements)
        ..where((t) => t.productId.equals(id))).get();
  return rows.fold<int>(0, (sum, row) => sum + row.quantity);
}

Matcher get _insufficient => throwsA(isA<SaleValidationException>().having(
    (e) => e.message, 'message', 'Insufficient stock'));

void main() {
  group('INV-1 repeated lines with negative stock prohibited', () {
    late AppDatabase db;
    setUp(() async => db = await _shop(allowNegativeStock: false));
    tearDown(() => db.close());

    Future<void> expectNothingWritten() async {
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.syncOperations).get(), isEmpty);
    }

    test('PIECE: 2 + 2 of 3 in stock is refused; 1 + 2 is accepted', () async {
      await expectLater(_sell(db, [('surf', 2000), ('surf', 2000)]), _insufficient);
      await expectNothingWritten();
      expect(await _stock(db, 'surf'), 3000);

      await _sell(db, [('surf', 1000), ('surf', 2000)]);
      expect(await _stock(db, 'surf'), 0);
    });

    test('loose kg: 600 g + 600 g of 1 kg is refused; 500 g + 500 g is accepted',
        () async {
      await expectLater(_sell(db, [('atta', 600), ('atta', 600)]), _insufficient);
      await expectNothingWritten();

      await _sell(db, [('atta', 500), ('atta', 500)]);
      expect(await _stock(db, 'atta'), 0);
    });

    test('loose liter: 750 ml + 300 ml of 1 L is refused; 750 ml + 250 ml is accepted',
        () async {
      await expectLater(_sell(db, [('oil', 750), ('oil', 300)]), _insufficient);
      await expectNothingWritten();

      await _sell(db, [('oil', 750), ('oil', 250)]);
      expect(await _stock(db, 'oil'), 0);
    });

    test('pack variants keep independent stock; repeats of one size add up',
        () async {
      // 250 g x2 and 500 g x1 together: each size within its own stock.
      await _sell(db, [('tapal-250', 2000), ('tapal-500', 1000)]);
      expect(await _stock(db, 'tapal-250'), 0);
      expect(await _stock(db, 'tapal-500'), 0);

      final fresh = await _shop(allowNegativeStock: false);
      addTearDown(fresh.close);
      await expectLater(
        _sell(fresh, [('tapal-250', 1000), ('tapal-500', 1000), ('tapal-250', 2000)]),
        _insufficient,
      );
      expect(await fresh.select(fresh.sales).get(), isEmpty);
      expect(await _stock(fresh, 'tapal-250'), 2000);
      expect(await _stock(fresh, 'tapal-500'), 1000);
    });
  });

  // Pilot rule (stock_policy.dart): a sale never oversells, even for a shop
  // whose allow_negative_stock is true (the column's default). The stored
  // setting is left as it is.
  group('no overselling, whatever the shop setting', () {
    late AppDatabase db;
    setUp(() async => db = await _shop(allowNegativeStock: true));
    tearDown(() => db.close());

    Future<void> expectNothingWritten() async {
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.syncOperations).get(), isEmpty);
    }

    Matcher refused(String name, int available, int requested,
            [String? unit]) =>
        throwsA(isA<InsufficientStockException>()
            .having((e) => e.message, 'message', 'Insufficient stock')
            .having((e) => e.productName, 'productName', name)
            .having((e) => e.availableQuantity, 'available', available)
            .having((e) => e.requestedQuantity, 'requested', requested)
            .having((e) => e.measureUnitName, 'unit', unit));

    test('repeated lines that exceed stock are refused; nothing is written',
        () async {
      await expectLater(_sell(db, [('surf', 2000), ('surf', 2000)]),
          refused('Surf', 3000, 4000));
      await expectNothingWritten();
      expect(await _stock(db, 'surf'), 3000);
      final shop = await db.select(db.shops).getSingle();
      expect(shop.allowNegativeStock, isTrue, reason: 'setting unchanged');
    });

    test('selling exactly the remaining stock is accepted; then zero stock '
        'is refused', () async {
      await _sell(db, [('surf', 3000)]);
      expect(await _stock(db, 'surf'), 0);
      await expectLater(_sell(db, [('surf', 1000)]), refused('Surf', 0, 1000));
      expect(await db.select(db.sales).get(), hasLength(1));
      expect(await _stock(db, 'surf'), 0);
    });

    test('loose kg/L and pack sizes are checked with their own stock',
        () async {
      await expectLater(_sell(db, [('atta', 600), ('atta', 600)]),
          refused('Atta', 1000, 1200, 'kg'));
      await expectLater(_sell(db, [('oil', 1001)]),
          refused('Oil', 1000, 1001, 'liter'));
      await expectLater(
          _sell(db, [('tapal-250', 1000), ('tapal-500', 1000), ('tapal-250', 2000)]),
          refused('Tapal Danedar 250 g', 2000, 3000));
      await expectNothingWritten();
      await _sell(db, [('atta', 500), ('atta', 500), ('oil', 1000),
        ('tapal-250', 2000), ('tapal-500', 1000)]);
      for (final id in ['atta', 'oil', 'tapal-250', 'tapal-500']) {
        expect(await _stock(db, id), 0, reason: id);
      }
    });

    test('stock already negative from history is kept and blocks sales',
        () async {
      // An earlier sale (before this rule) left Surf at -2.
      await db.into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
          id: 'old-sale', shopId: 'shop', productId: 'surf',
          type: InventoryMovementType.sale, quantity: -5000,
          referenceType: const Value('sale'), referenceId: const Value('old'),
          createdBy: 'owner', createdAt: _t,
        ),
      );
      expect(await _stock(db, 'surf'), -2000);
      await expectLater(_sell(db, [('surf', 1000)]), refused('Surf', -2000, 1000));
      expect(await _stock(db, 'surf'), -2000);
      expect(await db.select(db.inventoryMovements).get(), hasLength(6),
          reason: 'history untouched');
    });

    test('two checkouts for the last unit: exactly one succeeds', () async {
      await _sell(db, [('surf', 2000)]);
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          _sell(db, [('surf', 1000)]).then<Object>((s) => s, onError: (Object e) => e),
      ]);
      expect(results.whereType<CreatedSale>(), hasLength(1));
      expect(results.whereType<InsufficientStockException>(), hasLength(1));
      expect(await _stock(db, 'surf'), 0);
    });

    test('a product without stock tracking still sells', () async {
      await (db.update(db.shopProducts)..where((t) => t.id.equals('surf')))
          .write(const ShopProductsCompanion(stockTrackingEnabled: Value(false)));
      await _sell(db, [('surf', 5000)]);
      expect(await _stock(db, 'surf'), -2000);
    });

    test('the cart catalog follows the same rule', () async {
      final snapshot = await DriftPosCatalog(db, shopId: 'shop').load();
      expect(snapshot.allowNegativeStock, isFalse);
    });
  });

  group('RCP-1 receipt unit prices and discount', () {
    Future<void> pumpReceiptOf(WidgetTester tester, AppDatabase db, String saleId) async {
      final history = DriftSalesHistoryRepository(db, shopId: 'shop');
      final receipt = await tester.runAsync(
        () async => history.receipt(await history.detail((await history.sale(saleId))!)),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ReceiptView(receipt: receipt!))),
      ));
    }

    testWidgets('a discounted sale shows its stored discount and unit prices', (tester) async {
      final db = (await tester.runAsync(() => _shop(allowNegativeStock: true)))!;
      addTearDown(db.close);
      // Enough Atta for 2.5 kg: sales never oversell (stock_policy.dart).
      await tester.runAsync(() => db.into(db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
              id: 'more-atta', shopId: 'shop', productId: 'atta',
              type: InventoryMovementType.purchase, quantity: 2000,
              createdBy: 'owner', createdAt: _t,
            ),
          ));
      // Surf 2 x Rs 350 less Rs 50; Atta 2.5 kg at Rs 130/kg, no discount.
      final sale = (await tester.runAsync(
        () => LocalSaleService(db, const UuidV7Generator(), clock: () => _t).createSale(SaleDraft(
          shopId: 'shop', cashierId: 'owner', deviceId: 'device',
          lines: const [
            SaleLineDraft(productId: 'surf', quantity: 2000, discountMinor: 5000),
            SaleLineDraft(productId: 'atta', quantity: 2500),
          ],
          payments: const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 97500)],
        )),
      ))!;
      final stored = (await tester.runAsync(() => (db.select(db.sales)
            ..where((t) => t.id.equals(sale.saleId))).getSingle()))!;
      expect((stored.subtotal, stored.discountTotal, stored.grandTotal), (102500, 5000, 97500));

      await pumpReceiptOf(tester, db, sale.saleId);
      expect(find.text('2 × Surf  Rs 650.00'), findsOneWidget);
      expect(find.text('  @ Rs 350.00 each'), findsOneWidget);
      expect(find.text('2.5 kg × Atta  Rs 325.00'), findsOneWidget);
      expect(find.text('  @ Rs 130.00/kg'), findsOneWidget);
      expect(find.text('Subtotal Rs 1025.00'), findsOneWidget);
      expect(find.text('Discount -Rs 50.00'), findsOneWidget);
      expect(find.text('Total Rs 975.00'), findsOneWidget);
    });

    testWidgets('an undiscounted sale shows no discount line', (tester) async {
      final db = (await tester.runAsync(() => _shop(allowNegativeStock: true)))!;
      addTearDown(db.close);
      final sale = (await tester.runAsync(() => _sell(db, [('oil', 750)])))!;
      await pumpReceiptOf(tester, db, sale.saleId);
      expect(find.text('  @ Rs 175.00/L'), findsOneWidget);
      expect(find.textContaining('Discount'), findsNothing);
    });
  });

  group('IMG same-device and cross-device thumbnails', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('stage1_images_'));
    tearDown(() {
      ProductImageStore.instance = null;
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold a decoded file briefly; the OS temp dir is fine.
      }
    });

    final image = find.byKey(const ValueKey('product-image'));
    final placeholder = find.byKey(const ValueKey('product-image-placeholder'));
    Uint8List jpg() => img.encodeJpg(img.Image(width: 16, height: 16));

    Future<void> pumpThumbs(WidgetTester tester, List<ProductThumbnail> thumbs) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: thumbs))));
      // Let real file reads and decoding (and any decode error) complete.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    testWidgets('an image saved on this tablet shows after an app restart, '
        'keyed by the POS catalog product id', (tester) async {
      final db = (await tester.runAsync(() => _shop(allowNegativeStock: true)))!;
      addTearDown(db.close);
      final root = Directory('${temp.path}/product_images');
      // Session 1: the owner picks a photo for Surf on this tablet.
      await tester.runAsync(() async =>
          (await ProductImageStore.open(root)).save('surf', jpg()));
      // Restart: a fresh store indexes what is on disk.
      ProductImageStore.instance = (await tester.runAsync(() => ProductImageStore.open(root)))!;
      final products = (await tester.runAsync(
        () => DriftPosCatalog(db, shopId: 'shop').load(),
      ))!.products;
      final surf = products.singleWhere((p) => p.name == 'Surf');
      final atta = products.singleWhere((p) => p.name == 'Atta');

      await pumpThumbs(tester, [
        ProductThumbnail(productId: surf.id, imagePath: surf.imagePath),
        ProductThumbnail(productId: atta.id, imagePath: atta.imagePath),
      ]);
      expect(image, findsOneWidget);
      expect(placeholder, findsOneWidget);
    });

    testWidgets('a local image wins over a synced path', (tester) async {
      ProductImageStore.instance = (await tester.runAsync(() async {
        final store = await ProductImageStore.open(temp);
        await store.save('p1', jpg());
        return store;
      }))!;
      await pumpThumbs(tester, [
        const ProductThumbnail(productId: 'p1', imagePath: 'shop/p1.jpg'),
      ]);
      expect(image, findsOneWidget);
    });

    testWidgets('IMG-2: a Storage key with no local copy shows the placeholder '
        '(the cross-device case; needs the Storage design)', (tester) async {
      ProductImageStore.instance =
          (await tester.runAsync(() => ProductImageStore.open(temp)))!;
      await pumpThumbs(tester, [
        const ProductThumbnail(
          productId: 'from-other-device',
          imagePath: 'product-images/shop/from-other-device.jpg',
        ),
      ]);
      expect(placeholder, findsOneWidget);
      expect(image, findsNothing);
    });

    testWidgets('a corrupt stored image falls back to the placeholder', (tester) async {
      ProductImageStore.instance = (await tester.runAsync(() async {
        final store = await ProductImageStore.open(temp);
        await store.save('broken', Uint8List.fromList(List.filled(64, 7)));
        return store;
      }))!;
      await pumpThumbs(tester, [const ProductThumbnail(productId: 'broken')]);
      expect(placeholder, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
