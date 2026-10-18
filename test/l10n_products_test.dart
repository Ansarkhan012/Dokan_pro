// Stage 2B Batch 3: products, pack families and inventory in Urdu. Creating
// PIECE, loose kg / L and packaged products in Urdu (Urdu digits, mixed
// names, a language switch mid-form) yields exactly the same drafts as in
// English; validation messages are translated while keeping the entered
// label or barcode; inventory rows and history read in Urdu; real Roboto +
// Noto Nastaliq/Naskh metrics at phone and tablet sizes, text scale 1.0/1.3.
import 'dart:typed_data';

import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/format/measure_format.dart';
import 'package:dukaan_pro/core/images/product_image_processing.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/core/l10n/messages.dart';
import 'package:dukaan_pro/features/inventory/inventory_management_native.dart';
import 'package:dukaan_pro/features/inventory/inventory_models.dart';
import 'package:dukaan_pro/features/products/custom_product_dialog.dart';
import 'package:dukaan_pro/features/products/edit_product_dialog.dart';
import 'package:dukaan_pro/features/products/product_image_picker.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/products/product_management_native.dart'
    show categoryLabel;
import 'package:dukaan_pro/features/products/product_management_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));

const _dairy = 'd0000000-0000-0000-0000-000000000003';
const _categories = [
  ProductCategory(id: _dairy, name: 'Dairy'),
  ProductCategory(id: 'shop-cat', name: 'Pan Items'),
];

final class _NoPicker implements ProductImagePicker {
  @override
  Future<Uint8List?> pick() async => null;
}

void main() {
  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('product messages and units', () {
    String? familyError(
      ProductFamilyDraft family, {
      Set<String> used = const {},
    }) {
      try {
        ProductManagementService.validateFamily(family, existingBarcodes: used);
        return null;
      } on ProductValidationException catch (e) {
        return e.message;
      }
    }

    ProductFamilyDraft family(
      List<PackVariantDraft> variants, {
      String name = 'Tapal',
    }) => ProductFamilyDraft(
      familyId: 'f',
      name: name,
      categoryId: 'c',
      variants: variants,
    );
    PackVariantDraft pack(
      String label, {
      String? barcode,
      int sale = 100,
      int opening = 1000,
    }) => PackVariantDraft(
      productId: label,
      movementId: 'm$label',
      packLabel: label,
      barcode: barcode,
      purchasePriceMinor: 0,
      salePriceMinor: sale,
      openingQuantity: opening,
      lowStockLevel: 0,
    );

    test('every product message: English unchanged, Urdu translated', () {
      final messages = <String>[
        familyError(family([], name: ''))!,
        familyError(family([]))!,
        familyError(family([pack(' ')]))!,
        familyError(family([pack('250 g'), pack('250g')]))!,
        familyError(family([pack('250 g', barcode: '896')]), used: {'896'})!,
        familyError(family([pack('250 g', sale: 0)]))!,
        familyError(family([pack('250 g', opening: 1500)]))!,
        'This product is already in your shop',
        'Product name is required',
        'Category is required',
        'Prices cannot be negative',
        'Loose products are sold by weight (kg) or volume (L)',
        'Use at most $maxMeasurePresets quick quantities',
        'Use at most $maxMeasurePresets quick quantities.',
        'Quick quantities are not valid',
        'Stock values cannot be negative',
        'Enter valid non-negative values.',
        'Complete all required fields with valid values.',
        'Pack 250 g: enter a sale price and whole-pack stock.',
        const FamilyCreationIncomplete(
          created: ['a', 'b'],
          failedLabel: '1 kg',
          reason: 'it could not be saved',
        ).toString(),
        'Could not save the product. Please try again.',
        'Could not create the product. Please try again.',
        'Could not update product.',
        'Could not open that image. Try another.',
        'That quick quantity is already in the list.',
        'Keep at least one quick quantity.',
        'Enter a valid quantity and reason.',
        'Catalog search failed. Check internet and try again.',
      ];
      for (final source in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        try {
          prepareProductThumbnail(source);
        } on ProductImageException catch (e) {
          messages.add(e.message);
        }
      }
      expect(messages, contains('The selected file is empty.'));
      expect(messages, contains('Choose a JPG, PNG or WebP product image.'));
      for (final message in messages) {
        expect(localizedKnownMessage(_en, message), message, reason: message);
        final urdu = localizedKnownMessage(_ur, message);
        expect(urdu, isNotNull, reason: message);
        expect(urdu, isNot(message), reason: message);
      }
      // The entered label / barcode is kept exactly, isolated in Urdu.
      expect(
        localizedMessage(_ur, 'Pack size 250 g is listed twice'),
        _ur.prodErrPackTwice(isolateAuto('250 g')),
      );
      expect(
        localizedMessage(
          _ur,
          'Barcode 8964000000017 is already used in this shop',
        ),
        _ur.prodErrBarcodeUsed(isolateLtr('8964000000017')),
      );
      expect(
        localizedMessage(
          _ur,
          const FamilyCreationIncomplete(
            created: ['a'],
            failedLabel: '1 kg',
            reason: 'it could not be saved',
          ).toString(),
        ),
        _ur.prodErrFamilyIncomplete(
          isolateAuto('1 kg'),
          _ur.prodErrNotSaved,
          '1',
        ),
      );
    });

    test(
      'unit names: English exactly as each screen showed it; Urdu translated',
      () {
        for (final unit in ProductUnit.values) {
          expect(_en.unitName(unit.name, unit.label), unit.label);
          expect(_en.unitName(unit.name, unit.name), unit.name);
          expect(_ur.unitName(unit.name, unit.label), isNot(unit.label));
        }
        expect(_ur.unitName('kg', 'Kg'), 'کلو');
        expect(_ur.unitName('liter', 'Liter'), 'لیٹر');
        expect(_ur.unitName('crate', 'Crate'), 'Crate'); // unknown: unchanged
      },
    );

    testWidgets(
      'category labels: built-ins by id, shop categories as entered',
      (tester) async {
        late BuildContext urdu;
        await tester.pumpWidget(
          LocalizedMaterialApp(
            controller: LocaleController(initialLocale: LocaleController.urdu),
            home: Builder(
              builder: (c) {
                urdu = c;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(
          categoryLabel(urdu, id: _dairy, name: 'Dairy'),
          isolateAuto('دودھ اور ڈیری'),
        );
        expect(
          categoryLabel(urdu, id: 'shop-cat', name: 'Pan Items'),
          isolateAuto('Pan Items'),
        );
        expect(
          categoryLabel(urdu, id: null, name: 'Uncategorized'),
          isolateAuto('بغیر کیٹیگری'),
        );
        expect(
          categoryLabel(urdu, id: 'x', name: 'Dairy'),
          isolateAuto('Dairy'),
        ); // name alone never translates
      },
    );
  });

  group('Create Custom Product in Urdu (real fonts)', () {
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.nastaliq, 1.0),
      (Size(360, 800), UrduFont.naskh, 1.3),
      (Size(1340, 800), UrduFont.naskh, 1.0),
      (Size(1340, 800), UrduFont.nastaliq, 1.3),
      (Size(1024, 600), UrduFont.nastaliq, 1.0),
    ]) {
      final name =
          '${size.width.toInt()}x${size.height.toInt()} ${font.name} x$scale';

      testWidgets('PIECE: mixed name, Urdu digits, switch mid-form: $name', (
        tester,
      ) async {
        final h = await _open(tester, size, font, scale);
        expect(find.text(_ur.productsCreateCustom), findsOneWidget);
        await _type(tester, 'custom-product-name', 'Lux صابن (Large)');
        await _pickCategory(tester, isolateAuto('دودھ اور ڈیری'));
        expect(find.text(_ur.unitName('piece', 'Piece')), findsOneWidget);
        await _type(tester, 'custom-product-purchase', '۱۰۰');
        await _type(tester, 'custom-product-sale', '۱۲۰٫۵۰');
        await _type(tester, 'custom-product-opening', '۱۲');
        expect(_text(tester, 'custom-product-sale'), '120.50');

        // English mid-form: every typed value stays; labels switch.
        await h.controller.setLocale(LocaleController.english);
        await tester.pumpAndSettle();
        expect(find.text('Product name *'), findsOneWidget);
        expect(_text(tester, 'custom-product-name'), 'Lux صابن (Large)');
        expect(_text(tester, 'custom-product-sale'), '120.50');
        await h.controller.setLocale(LocaleController.urdu);
        await tester.pumpAndSettle();
        expect(find.text(_ur.customProductName), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _tap(tester, 'custom-product-create');
        final draft = h.drafts.single;
        expect(draft.input.name, 'Lux صابن (Large)');
        expect(draft.input.categoryId, _dairy);
        expect(draft.input.unit, ProductUnit.piece);
        expect(
          (
            draft.input.purchasePriceMinor,
            draft.input.salePriceMinor,
            draft.input.openingQuantity,
          ),
          (10000, 12050, 12000),
        );
        expect(draft.input.sellMode, SellMode.piece);
      });

      testWidgets('loose L and kg with Urdu presets: $name', (tester) async {
        final h = await _open(tester, size, font, scale);
        await _tap(tester, 'selling-loose');
        await _tap(tester, 'measure-liter');
        expect(find.text('${_ur.fieldSalePricePer('لیٹر')} *'), findsOneWidget);
        expect(find.text(_ur.fieldOpeningStockIn('لیٹر')), findsOneWidget);
        await _type(tester, 'custom-product-name', 'سرسوں کا تیل');
        await _pickCategory(tester, isolateAuto('Pan Items'));
        await _type(tester, 'preset-input', '۷۵۰');
        await _tap(tester, 'preset-add');
        expect(find.text(isolateLtr('750 ملی لیٹر')), findsOneWidget);
        await _type(tester, 'custom-product-purchase', '۴۰۰');
        await _type(tester, 'custom-product-sale', '۴۵۰');
        await _type(tester, 'custom-product-opening', '۲٫۵');
        expect(tester.takeException(), isNull);
        await _tap(tester, 'custom-product-create');
        final input = h.drafts.single.input;
        expect(
          (input.unit, input.sellMode),
          (ProductUnit.liter, SellMode.measured),
        );
        expect((input.salePriceMinor, input.openingQuantity), (45000, 2500));
        expect(input.measurePresets, contains(750));
        expect(input.categoryId, 'shop-cat');
      });

      testWidgets(
        'packaged variants: independent price, barcode, stock: $name',
        (tester) async {
          final h = await _open(tester, size, font, scale);
          await _tap(tester, 'selling-packaged');
          expect(find.text(_ur.customFamilyName), findsOneWidget);
          await _type(tester, 'custom-product-name', 'Tapal Danedar');
          await _pickCategory(tester, isolateAuto('دودھ اور ڈیری'));
          await _type(tester, 'pack-row-0-label', '250 g');
          await _type(tester, 'pack-row-0-barcode', '۸۹۶۴۰۰۰۰۰۰۰۱۷');
          await _type(tester, 'pack-row-0-sale', '۴۱۰');
          await _type(tester, 'pack-row-0-opening', '۲۴');
          expect(_text(tester, 'pack-row-0-barcode'), '8964000000017');
          await _tap(tester, 'pack-add-row');
          await _type(tester, 'pack-row-1-label', '500 g');
          await _type(tester, 'pack-row-1-barcode', '8964000000017');
          await _type(tester, 'pack-row-1-sale', '800');
          await _type(tester, 'pack-row-1-opening', '6');
          // Same barcode twice: refused in Urdu, the barcode kept exactly.
          await _tap(tester, 'custom-product-create');
          expect(
            find.text(_ur.prodErrBarcodeUsed(isolateLtr('8964000000017'))),
            findsOneWidget,
          );
          expect(h.drafts, isEmpty);
          // The on-screen error re-translates when the language changes.
          await h.controller.setLocale(LocaleController.english);
          await tester.pumpAndSettle();
          expect(
            find.text('Barcode 8964000000017 is already used in this shop'),
            findsOneWidget,
          );
          await h.controller.setLocale(LocaleController.urdu);
          await tester.pumpAndSettle();
          await _type(tester, 'pack-row-1-barcode', '8964000000024');
          expect(tester.takeException(), isNull);
          await _tap(tester, 'custom-product-create');
          final variants = h.drafts.single.family!.variants;
          expect(
            [
              for (final v in variants)
                (v.packLabel, v.barcode, v.salePriceMinor, v.openingQuantity),
            ],
            [
              ('250 g', '8964000000017', 41000, 24000),
              ('500 g', '8964000000024', 80000, 6000),
            ],
          );
        },
      );
    }

    testWidgets('empty form: Urdu error, re-translated after a switch', (
      tester,
    ) async {
      final h = await _open(
        tester,
        const Size(360, 800),
        UrduFont.nastaliq,
        1.0,
      );
      await _tap(tester, 'custom-product-create');
      expect(find.text(_ur.prodErrRequiredFields), findsOneWidget);
      await h.controller.setLocale(LocaleController.english);
      await tester.pumpAndSettle();
      expect(
        find.text('Complete all required fields with valid values.'),
        findsOneWidget,
      );
    });

    testWidgets('English form is unchanged', (tester) async {
      final h = await _open(
        tester,
        const Size(1340, 800),
        UrduFont.nastaliq,
        1.0,
        locale: LocaleController.english,
      );
      expect(find.text('Create Custom Product'), findsOneWidget);
      expect(find.text('Purchase price *'), findsOneWidget);
      expect(find.text('Piece'), findsOneWidget);
      await _tap(tester, 'selling-loose');
      expect(find.text('Sale price per kg *'), findsOneWidget);
      expect(find.text('Opening stock (kg)'), findsOneWidget);
      expect(find.text('Low-stock alert at (kg)'), findsOneWidget);
      expect(h.drafts, isEmpty);
    });
  });

  group('Edit product and duplicate warning in Urdu (real fonts)', () {
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.nastaliq, 1.3),
      (Size(1340, 800), UrduFont.naskh, 1.0),
    ]) {
      testWidgets('loose kg edit ${size.width.toInt()} ${font.name} x$scale', (
        tester,
      ) async {
        ProductEdit? saved;
        final c = LocaleController(
          initialLocale: LocaleController.urdu,
          initialUrduFont: font,
        );
        await _pumpDialog(
          tester,
          size,
          scale,
          c,
          EditProductDialog(
            product: const ManagedProduct(
              id: 'atta',
              name: 'آٹا (Chakki)',
              categoryName: 'Staples',
              unit: 'kg',
              purchasePriceMinor: 12000,
              salePriceMinor: 13000,
              stockQuantity: 37500,
              lowStockLevel: 5000,
              isActive: true,
              isCustom: true,
              sellMode: SellMode.measured,
              measurePresets: [500, 1000],
            ),
            onSubmit: (edit) async => saved = edit,
          ),
        );
        expect(find.text(_ur.editTitle), findsOneWidget);
        expect(find.text(isolateAuto('آٹا (Chakki)')), findsOneWidget);
        expect(find.text(_ur.editLooseWeight), findsOneWidget);
        expect(find.text(_ur.fieldSalePricePer('کلو')), findsOneWidget);
        expect(find.text(isolateLtr('500 گرام')), findsOneWidget);
        await _type(tester, 'edit-product-sale', '۱۳۵');
        expect(tester.takeException(), isNull);
        await _tap(tester, 'edit-product-save');
        expect(
          (
            saved!.salePriceMinor,
            saved!.purchasePriceMinor,
            saved!.lowStockLevel,
          ),
          (13500, 12000, 5000),
        );
      });
    }

    testWidgets('possible duplicate', (tester) async {
      final c = LocaleController(initialLocale: LocaleController.urdu);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Future<bool> answer;
      await tester.pumpWidget(
        LocalizedMaterialApp(
          controller: c,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => answer = confirmPossibleDuplicate(context, [
                  for (var i = 0; i < 7; i++)
                    (name: 'Lux Soap $i', sameBarcode: i == 0),
                ]),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(_ur.dupTitle), findsOneWidget);
      expect(
        find.text('• ${isolateAuto('Lux Soap 0')}  ${_ur.dupSameBarcode}'),
        findsOneWidget,
      );
      expect(find.text(_ur.dupMore('2')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(_ur.dupCreateAnyway));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
    });
  });

  group('Inventory in Urdu (real fonts)', () {
    for (final (size, font, scale) in const [
      (Size(360, 800), UrduFont.nastaliq, 1.3),
      (Size(1340, 800), UrduFont.naskh, 1.0),
    ]) {
      testWidgets(
        'stock rows and history ${size.width.toInt()} ${font.name} x$scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            LocalizedMaterialApp(
              controller: LocaleController(
                initialLocale: LocaleController.urdu,
                initialUrduFont: font,
              ),
              home: Scaffold(
                body: ListView(
                  children: [
                    InventoryStockRow(
                      product: const InventoryProductRow(
                        id: 'atta',
                        name: 'Atta (Chakki)',
                        unit: 'kg',
                        stockQuantity: 2000,
                        lowStockLevel: 5000,
                        isActive: true,
                        barcode: '8964000000031',
                      ),
                      onAdjust: () {},
                    ),
                    InventoryStockRow(
                      product: const InventoryProductRow(
                        id: 'surf',
                        name: 'سرف',
                        unit: 'piece',
                        stockQuantity: 0,
                        lowStockLevel: 0,
                        isActive: false,
                      ),
                      onAdjust: () {},
                    ),
                    InventoryMovementTile(
                      movement: InventoryMovementRow(
                        id: 'm1',
                        productName: 'Coke',
                        type: InventoryMovementType.returnIn,
                        quantity: 2000,
                        createdAt: DateTime(2026, 10, 5, 13, 17),
                        referenceType: 'sale_void',
                        reference: 'B-0042',
                        note: 'گاہک نے واپس کیا',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('کلو • ${isolateLtr('8964000000031')}'),
            findsOneWidget,
          );
          expect(find.text(_ur.posLowStock), findsOneWidget);
          expect(find.text(_ur.inventoryOutOfStock), findsOneWidget);
          expect(find.text(_ur.productsInactive), findsOneWidget);
          expect(find.text(_ur.inventoryAdjust), findsNWidgets(2));
          expect(find.text('عدد • ${_ur.posNoBarcode}'), findsOneWidget);
          expect(
            find.text(
              '${_ur.movementVoid} • ${isolateLtr('B-0042')} • 5 اکتوبر 2026، 1:17 PM',
            ),
            findsOneWidget,
          );
          expect(find.text(isolateLtr('+2')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    test('movement labels: English unchanged', () {
      for (final type in InventoryMovementType.values) {
        for (final ref in [null, 'sale_void']) {
          expect(
            localizedInventoryMovementLabel(_en, type, referenceType: ref),
            inventoryMovementLabel(type, referenceType: ref),
          );
        }
      }
    });
  });
}

final class _Harness {
  _Harness(this.controller);
  final LocaleController controller;
  final drafts = <CustomProductDraft>[];
}

Future<_Harness> _open(
  WidgetTester tester,
  Size size,
  UrduFont font,
  double scale, {
  Locale locale = LocaleController.urdu,
}) async {
  final h = _Harness(
    LocaleController(initialLocale: locale, initialUrduFont: font),
  );
  await _pumpDialog(
    tester,
    size,
    scale,
    h.controller,
    CustomProductDialog(
      categories: _categories,
      picker: _NoPicker(),
      onSubmit: (draft) async => h.drafts.add(draft),
    ),
  );
  return h;
}

Future<void> _pumpDialog(
  WidgetTester tester,
  Size size,
  double scale,
  LocaleController controller,
  Widget dialog,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    LocalizedMaterialApp(
      controller: controller,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showDialog<Object>(context: context, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
  await tester.pump();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

Future<void> _pickCategory(WidgetTester tester, String label) async {
  await _tap(tester, 'custom-product-category');
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
