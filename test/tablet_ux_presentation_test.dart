import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/format/display_format.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/inventory/drift_inventory_repository.dart';
import 'package:dukaan_pro/features/inventory/inventory_management_native.dart';
import 'package:dukaan_pro/features/inventory/inventory_models.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/products/custom_product_dialog.dart';
import 'package:dukaan_pro/features/products/edit_product_dialog.dart';
import 'package:dukaan_pro/features/products/product_duplicates.dart';
import 'package:dukaan_pro/features/products/product_image_picker.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/sales/domain/bill_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ManagedProduct _managed({
  String id = 'p1',
  String name = 'Surf Excel 1kg',
  String? barcode,
  int stock = 9000,
  int? low = 2000,
  bool active = true,
}) => ManagedProduct(
  id: id,
  name: name,
  categoryName: 'Grocery',
  unit: 'piece',
  purchasePriceMinor: 85000,
  salePriceMinor: 95000,
  stockQuantity: stock,
  lowStockLevel: low,
  isActive: active,
  isCustom: true,
  barcode: barcode,
);

void main() {
  group('display formatting', () {
    final at = DateTime(2026, 10, 5, 12, 3, 35, 123);

    test('dates and times read like a shop, not a database', () {
      expect(formatDisplayDate(at), '5 Oct 2026');
      expect(formatDisplayTime(at), '12:03 PM');
      expect(formatDisplayTime(DateTime(2026, 1, 1, 0, 7)), '12:07 AM');
      expect(formatDisplayTime(DateTime(2026, 1, 1, 13, 17)), '1:17 PM');
      expect(formatDisplayDateTime(at), '5 Oct 2026 • 12:03 PM');
      expect(
        formatDisplayDateTime(at, separator: ', '),
        '5 Oct 2026, 12:03 PM',
      );
      expect(formatDisplayDateTime(at), isNot(contains('.000')));
    });

    test('relative dates say Today and Yesterday', () {
      final now = DateTime(2026, 10, 18, 15);
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 18, 13, 14), now: now),
        'Today, 1:14 PM',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 17, 9, 2), now: now),
        'Yesterday, 9:02 AM',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 1, 9, 2), now: now),
        '1 Oct 2026, 9:02 AM',
      );
    });

    test('payment methods, identifiers and quantities are humanized', () {
      expect(paymentMethodLabel('cash'), 'Cash');
      expect(paymentMethodLabel('digital'), 'Digital');
      expect(paymentMethodLabel('credit'), 'Udhaar');
      expect(paymentMethodLabel('Split'), 'Split');
      expect(humanizeIdentifier('pilot_basic'), 'Pilot basic');
      expect(humanizeIdentifier('openingStock'), 'Opening stock');
      expect(formatDisplayQuantity(39000), '39');
      expect(formatDisplayQuantity(1500), '1.5');
      expect(formatSignedQuantity(39000), '+39');
      expect(formatSignedQuantity(-2000), '-2');
      expect(formatSignedQuantity(0), '0');
    });
  });

  group('likely duplicate products', () {
    final existing = [
      _managed(id: 'a', name: 'Surf Excel 1kg', barcode: '8964001'),
      _managed(id: 'b', name: 'Rice 5kg'),
    ];

    test('case, spacing and punctuation are ignored for names', () {
      expect(normalizeProductName('Surf excel 1 Kg'), 'surfexcel1kg');
      final matches = findLikelyDuplicates(existing, name: 'Surf excel 1 Kg');
      expect(matches.single.product.id, 'a');
      expect(matches.single.sameBarcode, isFalse);
    });

    test('same barcode matches even with a different name', () {
      final matches = findLikelyDuplicates(
        existing,
        name: 'Detergent',
        barcode: ' 8964001 ',
      );
      expect(matches.single.product.id, 'a');
      expect(matches.single.sameBarcode, isTrue);
    });

    test('different products and empty barcodes do not match', () {
      expect(findLikelyDuplicates(existing, name: 'Surf Excel 2kg'), isEmpty);
      expect(
        findLikelyDuplicates(existing, name: 'Sugar', barcode: ''),
        isEmpty,
      );
    });
  });

  group('inventory presentation', () {
    test('movement labels never show raw enum names', () {
      expect(
        inventoryMovementLabel(InventoryMovementType.openingStock),
        'Opening stock',
      );
      expect(inventoryMovementLabel(InventoryMovementType.sale), 'Sale');
      expect(
        inventoryMovementLabel(
          InventoryMovementType.returnIn,
          referenceType: 'sale_return',
        ),
        'Return',
      );
      expect(
        inventoryMovementLabel(
          InventoryMovementType.returnIn,
          referenceType: 'sale_void',
        ),
        'Void',
      );
      expect(
        inventoryMovementLabel(InventoryMovementType.manualAdjustment),
        'Adjustment',
      );
      for (final type in InventoryMovementType.values) {
        expect(inventoryMovementLabel(type), isNot(type.name));
      }
    });

    testWidgets('movement tile shows label, bill, date and signed quantity', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                InventoryMovementTile(
                  movement: InventoryMovementRow(
                    id: 'm1',
                    productName: 'Rice',
                    type: InventoryMovementType.openingStock,
                    quantity: 39000,
                    createdAt: DateTime(2026, 10, 5, 12, 3, 35),
                    note: 'Counted',
                  ),
                ),
                InventoryMovementTile(
                  movement: InventoryMovementRow(
                    id: 'm2',
                    productName: 'Rice',
                    type: InventoryMovementType.sale,
                    quantity: -2000,
                    createdAt: DateTime(2026, 10, 5, 13, 17),
                    referenceType: 'sale',
                    reference: 'Bill #0509F516',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Opening stock • 5 Oct 2026, 12:03 PM'), findsOneWidget);
      expect(find.text('+39'), findsOneWidget);
      expect(
        find.text('Sale • Bill #0509F516 • 5 Oct 2026, 1:17 PM'),
        findsOneWidget,
      );
      expect(find.text('-2'), findsOneWidget);
      expect(find.textContaining('openingStock'), findsNothing);
      expect(find.textContaining('.000'), findsNothing);
    });

    for (final width in [420.0, 800.0, 1280.0]) {
      testWidgets('stock row distinguishes Low / Out at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var adjusted = 0;
        InventoryProductRow row(String id, int stock) => InventoryProductRow(
          id: id,
          name: 'A long grocery product name $id that may need truncation',
          unit: 'kg',
          barcode: '8964001000011',
          stockQuantity: stock,
          lowStockLevel: 2000,
          isActive: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  for (final p in [
                    row('ok', 9000),
                    row('low', 1000),
                    row('out', 0),
                  ])
                    InventoryStockRow(product: p, onAdjust: () => adjusted++),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Low stock'), findsOneWidget);
        expect(find.text('Out of stock'), findsOneWidget);
        expect(find.text('in stock'), findsOneWidget);
        expect(find.text('Kg • 8964001000011'), findsNWidgets(3));
        // Adjust sits right beside the stock figure it changes.
        final stock = tester.getRect(find.byKey(const ValueKey('stock-low')));
        final adjust = tester.getRect(find.text('Adjust').at(1));
        expect(adjust.left - stock.right, lessThan(140));
        await tester.tap(find.text('Adjust').at(2));
        expect(adjusted, 1);
      });
    }

    test('history resolves bill references without changing records', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final t = DateTime.utc(2026, 10, 5, 7);
      const saleId = '0199a1b2-c3d4-7e5f-8a9b-0509f5160000';
      await db
          .into(db.shopProducts)
          .insert(
            ShopProductsCompanion.insert(
              id: 'rice',
              shopId: 'shop',
              customName: const Value('Rice'),
              purchasePrice: 1,
              salePrice: 2,
              createdAt: t,
              updatedAt: t,
            ),
          );
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              shopId: 'shop',
              cashierId: 'c',
              deviceId: 'd',
              subtotal: 2,
              discountTotal: 0,
              taxTotal: 0,
              grandTotal: 2,
              paymentStatus: PaymentStatus.paid,
              saleStatus: SaleStatus.completed,
              createdAt: t,
            ),
          );
      await db
          .into(db.saleReturns)
          .insert(
            SaleReturnsCompanion.insert(
              id: 'ret',
              shopId: 'shop',
              originalSaleId: saleId,
              deviceId: 'd',
              refundMethod: PaymentMethod.cash,
              refundAmount: 2,
              reason: 'Torn bag',
              createdBy: 'o',
              createdAt: t,
            ),
          );
      await db
          .into(db.saleVoids)
          .insert(
            SaleVoidsCompanion.insert(
              id: 'void',
              shopId: 'shop',
              originalSaleId: saleId,
              deviceId: 'd',
              amount: 2,
              reason: 'Mistake',
              paymentBreakdown: '{}',
              createdBy: 'o',
              createdAt: t,
            ),
          );
      await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: 'pur',
              shopId: 'shop',
              invoiceNumber: const Value('INV-77'),
              subtotal: 1,
              discountTotal: 0,
              total: 1,
              paymentStatus: PaymentStatus.paid,
              createdBy: 'o',
              createdAt: t,
            ),
          );
      Future<void> movement(
        String id,
        InventoryMovementType type,
        int quantity,
        String? refType,
        String? refId,
        int minute,
      ) => db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              id: id,
              shopId: 'shop',
              productId: 'rice',
              type: type,
              quantity: quantity,
              referenceType: Value(refType),
              referenceId: Value(refId),
              createdBy: 'o',
              createdAt: t.add(Duration(minutes: minute)),
            ),
          );
      await movement(
        'm1',
        InventoryMovementType.openingStock,
        5000,
        null,
        null,
        1,
      );
      await movement(
        'm2',
        InventoryMovementType.sale,
        -1000,
        'sale',
        saleId,
        2,
      );
      await movement(
        'm3',
        InventoryMovementType.returnIn,
        1000,
        'sale_return',
        'ret',
        3,
      );
      await movement(
        'm4',
        InventoryMovementType.returnIn,
        1000,
        'sale_void',
        'void',
        4,
      );
      await movement(
        'm5',
        InventoryMovementType.purchase,
        3000,
        'purchase',
        'pur',
        5,
      );
      await movement(
        'm6',
        InventoryMovementType.sale,
        -1000,
        'sale',
        'missing',
        6,
      );
      final before = await db.select(db.inventoryMovements).get();

      final rows = {
        for (final r in await DriftInventoryRepository(
          db,
          shopId: 'shop',
        ).history())
          r.id: r,
      };
      expect(rows, hasLength(6));
      final bill = billReference(saleId);
      expect(rows['m1']!.reference, isNull);
      expect(rows['m2']!.reference, bill);
      expect(rows['m3']!.reference, bill);
      expect(rows['m4']!.reference, bill);
      expect(rows['m4']!.referenceType, 'sale_void');
      expect(rows['m5']!.reference, 'Invoice INV-77');
      expect(rows['m6']!.reference, isNull, reason: 'never invented');
      expect(await db.select(db.inventoryMovements).get(), before);
    });
  });

  group('product grid card', () {
    for (final width in [150.0, 170.0, 190.0, 260.0]) {
      testWidgets('price stays on one line at card width $width', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: width,
                height: 150,
                child: PosProductCard(
                  product: const PosProduct(
                    id: 'p',
                    name: 'Product with a fairly long name',
                    salePriceMinor: 1234500,
                    stockQuantity: 9000,
                    stockTrackingEnabled: true,
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Rs 12345.00'), findsOneWidget);
        expect(find.text('Add'), findsOneWidget);
        expect(
          tester.getSize(
            find.byKey(const ValueKey('product-image-placeholder')),
          ),
          const Size(64, 64),
        );
      });
    }
  });

  group('product dialogs', () {
    Future<void> openDialog(
      WidgetTester tester,
      Widget dialog, {
      Size size = const Size(1280, 800),
      double keyboard = 0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<Object?>(
                  context: context,
                  builder: (_) => dialog,
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

    testWidgets('edit uses the shared form and submits parsed values', (
      tester,
    ) async {
      ProductEdit? submitted;
      await openDialog(
        tester,
        EditProductDialog(
          product: _managed(),
          onSubmit: (edit) async => submitted = edit,
          picker: _NoPicker(),
        ),
      );
      expect(find.text('Edit product'), findsOneWidget);
      expect(find.text('Choose product image'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-sale')),
        '990.50',
      );
      await tester.tap(find.byKey(const ValueKey('edit-product-save')));
      await tester.pumpAndSettle();
      expect(submitted!.salePriceMinor, 99050);
      expect(submitted!.purchasePriceMinor, 85000);
      expect(submitted!.lowStockLevel, 2000);
      expect(submitted!.isActive, isTrue);
      expect(submitted!.newImage, isNull);
      expect(submitted!.removeImage, isFalse);
      expect(find.text('Edit product'), findsNothing);
    });

    testWidgets('failed edit keeps the dialog open with the error', (
      tester,
    ) async {
      await openDialog(
        tester,
        EditProductDialog(
          product: _managed(),
          onSubmit: (_) async => throw StateError('offline'),
          picker: _NoPicker(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-product-save')));
      await tester.pumpAndSettle();
      expect(find.text('Could not update product.'), findsOneWidget);
      expect(find.text('Edit product'), findsOneWidget);
    });

    for (final (size, keyboard) in const [
      (Size(1280, 800), 420.0),
      (Size(1024, 600), 340.0),
      (Size(800, 1280), 420.0),
    ]) {
      testWidgets('edit has no overflow at $size with keyboard $keyboard', (
        tester,
      ) async {
        await openDialog(
          tester,
          EditProductDialog(
            product: _managed(),
            onSubmit: (_) async {},
            picker: _NoPicker(),
          ),
          size: size,
          keyboard: keyboard,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-product-save')),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('going back from a duplicate warning keeps the form', (
      tester,
    ) async {
      var attempts = 0;
      await openDialog(
        tester,
        CustomProductDialog(
          categories: const [ProductCategory(id: 'c', name: 'Grocery')],
          picker: _NoPicker(),
          onSubmit: (_) async {
            attempts++;
            throw const CustomProductSubmitCancelled();
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-product-name')),
        'Surf excel 1 Kg',
      );
      await tester.tap(find.byKey(const ValueKey('custom-product-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grocery').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-product-purchase')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-product-sale')),
        '2',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-product-create')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-product-create')));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('Create Custom Product'), findsOneWidget);
      expect(find.text('Surf excel 1 Kg'), findsOneWidget);
      // Unlocked again with no error shown.
      expect(find.text('Create Product'), findsOneWidget);
      expect(find.text('* Required'), findsOneWidget);
    });

    testWidgets('duplicate warning lets the owner continue intentionally', (
      tester,
    ) async {
      bool? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => decision = await confirmPossibleDuplicate(
                context,
                [(name: 'Surf Excel 1kg', sameBarcode: true)],
              ),
              child: const Text('check'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();
      expect(find.text('This product may already exist'), findsOneWidget);
      expect(find.textContaining('Surf Excel 1kg'), findsOneWidget);
      expect(find.textContaining('same barcode'), findsOneWidget);
      await tester.tap(find.text('Create anyway'));
      await tester.pumpAndSettle();
      expect(decision, isTrue);

      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(decision, isFalse);
    });
  });
}

final class _NoPicker implements ProductImagePicker {
  @override
  Future<Uint8List?> pick() async => null;
}
