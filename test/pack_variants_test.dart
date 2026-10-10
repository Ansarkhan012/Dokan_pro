// U3 packaged product families on the device: grouping and search, family
// validation and safe retry, the owner family editor, the grouped cashier
// card and pack selector, separate per-size bill lines, and per-size stock
// and snapshots in a local sale.
import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/pos/measured_quantity_picker.dart';
import 'package:dukaan_pro/features/pos/pack_selector.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart' hide formatPkr;
import 'package:dukaan_pro/features/products/custom_product_dialog.dart';
import 'package:dukaan_pro/features/products/drift_product_management_repository.dart';
import 'package:dukaan_pro/features/products/product_management_gateway.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/products/product_management_service.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PosProduct _pack(String id, String label, int price, int stock, {String? barcode}) => PosProduct(
      id: id,
      name: 'Tapal Danedar $label',
      salePriceMinor: price,
      stockQuantity: stock,
      stockTrackingEnabled: true,
      barcode: barcode,
      familyId: 'tapal',
      familyName: 'Tapal Danedar',
      packLabel: label,
    );

final _t250 = _pack('t250', '250 g', 29000, 24000, barcode: '8964000000250');
final _t500 = _pack('t500', '500 g', 55000, 18000, barcode: '8964000000500');
final _t1kg = _pack('t1kg', '1 kg', 105000, 8000, barcode: '8964000001000');
const _surf = PosProduct(id: 'surf', name: 'Surf', salePriceMinor: 35000, stockQuantity: 9000, stockTrackingEnabled: true);
const _atta = PosProduct(
  id: 'atta', name: 'Atta', salePriceMinor: 13000, stockQuantity: 40000,
  stockTrackingEnabled: true, measureUnit: MeasureUnit.kg);

PackVariantDraft _variant(String id, String label, int sale, {String? barcode, int opening = 10000, int low = 2000}) =>
    PackVariantDraft(
      productId: 'p-$id', movementId: 'm-$id', packLabel: label, barcode: barcode,
      purchasePriceMinor: sale - 4000, salePriceMinor: sale, openingQuantity: opening, lowStockLevel: low);

ProductFamilyDraft _family(List<PackVariantDraft> variants) =>
    ProductFamilyDraft(familyId: 'fam', name: 'Tapal Danedar', categoryId: 'tea', variants: variants);

void main() {
  group('grouping and search', () {
    test('explicit family links make one entry; nothing else is grouped', () {
      // A legacy product with the same name is NOT grouped (no family id).
      const legacy = PosProduct(id: 'legacy', name: 'Tapal Danedar 250 g', salePriceMinor: 30000,
          stockQuantity: 1000, stockTrackingEnabled: true);
      final entries = groupCatalog([_surf, _t1kg, legacy, _t250, _atta, _t500]);
      expect(entries.map((e) => e.isFamily), [false, true, false, false]);
      final family = entries[1];
      expect(family.name, 'Tapal Danedar');
      expect(family.variants.map((v) => v.id), ['t250', 't500', 't1kg'], reason: 'smallest price first');
      expect(family.fromPriceMinor, 29000);
      expect(entries[2].product!.id, 'legacy');
      expect(entries[3].product!.id, 'atta');
    });

    test('a family with one visible size is a plain card', () {
      final entries = groupCatalog([_t500]);
      expect((entries.single.isFamily, entries.single.product!.id), (false, 't500'));
    });

    test('search finds the family by name, the size by label, the pack by barcode', () {
      final all = [_t250, _t500, _t1kg, _surf];
      List<String> find(String q) => all.where((p) => matchesPosSearch(p, q)).map((p) => p.id).toList();
      expect(find('Tapal'), ['t250', 't500', 't1kg']);
      expect(find('danedar'), ['t250', 't500', 't1kg']);
      expect(find('500g'), ['t500']);
      expect(find('500 g'), ['t500']);
      expect(find('8964000001000'), ['t1kg']);
      expect(find('89640000010'), isEmpty, reason: 'barcodes match exactly');
      expect(find(''), hasLength(4));
    });

    test('pack stock rules and labels', () {
      final empty = _pack('e', '1 kg', 1000, 0);
      expect(canAddPack(empty, allowNegativeStock: false), isFalse);
      expect(canAddPack(empty, allowNegativeStock: true), isTrue);
      expect(canAddPack(_t1kg, allowNegativeStock: false, alreadyInCart: 7000), isTrue);
      expect(canAddPack(_t1kg, allowNegativeStock: false, alreadyInCart: 8000), isFalse);
      expect((packCountLabel(1000), packCountLabel(24000)), ('1 pack', '24 packs'));
    });
  });

  group('family validation and creation', () {
    test('a valid family of three is created as three piece products, in order', () async {
      final gateway = _IdempotentGateway();
      final ids = await ProductManagementService(gateway, _NoIds()).createFamily(
        shopId: 'shop', deviceId: 'd',
        family: _family([_variant('250', '250 g', 29000), _variant('500', '500 g', 55000), _variant('1kg', '1 kg', 105000)]),
      );
      expect(ids, ['p-250', 'p-500', 'p-1kg']);
      expect(gateway.rows.values.map((i) => (i.familyId, i.packLabel, i.unit, i.sellMode, i.name)).toSet(), {
        ('fam', '250 g', ProductUnit.pack, SellMode.piece, 'Tapal Danedar'),
        ('fam', '500 g', ProductUnit.pack, SellMode.piece, 'Tapal Danedar'),
        ('fam', '1 kg', ProductUnit.pack, SellMode.piece, 'Tapal Danedar'),
      });
      expect(gateway.rows['p-500']!.salePriceMinor, 55000);
      expect(gateway.movements, ['m-250', 'm-500', 'm-1kg'], reason: 'one opening movement per size');
    });

    test('a partial failure reports exactly what exists; a retry finishes without duplicates', () async {
      final gateway = _IdempotentGateway()..failOnce = 'p-500';
      final service = ProductManagementService(gateway, _NoIds());
      final draft = _family([_variant('250', '250 g', 29000), _variant('500', '500 g', 55000), _variant('1kg', '1 kg', 105000)]);
      final failure = await service
          .createFamily(shopId: 'shop', deviceId: 'd', family: draft)
          .then<FamilyCreationIncomplete?>((_) => null, onError: (Object e) => e as FamilyCreationIncomplete);
      expect(failure!.created, ['p-250']);
      expect(failure.failedLabel, '500 g');
      expect(failure.toString(), contains('press Create again'));
      expect(gateway.rows.keys, ['p-250']);

      final ids = await service.createFamily(shopId: 'shop', deviceId: 'd', family: draft);
      expect(ids, ['p-250', 'p-500', 'p-1kg']);
      expect(gateway.movements, ['m-250', 'm-500', 'm-1kg'], reason: 'no second opening stock for 250 g');
      expect(gateway.rows, hasLength(3));
    });

    test('invalid families are refused before anything is sent', () {
      final gateway = _IdempotentGateway();
      final service = ProductManagementService(gateway, _NoIds());
      void refused(ProductFamilyDraft family, String message, {Set<String> existing = const {}}) => expect(
            () => service.createFamily(shopId: 'shop', deviceId: 'd', family: family, existingBarcodes: existing),
            throwsA(isA<ProductValidationException>().having((e) => e.message, 'message', contains(message))));
      refused(_family([]), 'at least one pack size');
      refused(_family([_variant('a', '500 g', 55000), _variant('b', '500G', 56000)]), 'listed twice');
      refused(_family([_variant('a', '', 55000)]), 'size label');
      refused(_family([_variant('a', '250 g', 29000, barcode: '111'), _variant('b', '500 g', 55000, barcode: '111')]),
          'already used');
      refused(_family([_variant('a', '250 g', 29000, barcode: '222')]), 'already used', existing: {'222'});
      refused(_family([_variant('a', '250 g', 0)]), 'sale price');
      refused(_family([_variant('a', '250 g', 29000, opening: 1500)]), 'whole packs');
      refused(const ProductFamilyDraft(familyId: 'f', name: ' ', categoryId: 'c', variants: []), 'family name');
      expect(gateway.rows, isEmpty);
    });
  });

  group('owner family editor', () {
    Future<void> openDialog(WidgetTester tester, CustomProductDialog dialog, void Function(CustomProductDraft?) done) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => done(await showDialog<CustomProductDraft>(context: context, builder: (_) => dialog)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, String key, String text) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.enterText(find.byKey(ValueKey(key)), text);
      await tester.pump();
    }

    Future<void> fillRow(WidgetTester tester, int i, String label, String sale, String cost, String opening,
        {String barcode = ''}) async {
      await fill(tester, 'pack-row-$i-label', label);
      await fill(tester, 'pack-row-$i-barcode', barcode);
      await fill(tester, 'pack-row-$i-sale', sale);
      await fill(tester, 'pack-row-$i-purchase', cost);
      await fill(tester, 'pack-row-$i-opening', opening);
      await fill(tester, 'pack-row-$i-low', '2');
    }

    Future<void> fillFamily(WidgetTester tester) async {
      await tapKey(tester, 'selling-packaged');
      expect(find.text('Product family name *'), findsOneWidget);
      expect(find.text('Pack size / label'), findsNothing, reason: 'single-piece fields hidden');
      await fill(tester, 'custom-product-name', 'Tapal Danedar');
      await tapKey(tester, 'custom-product-category');
      await tester.tap(find.text('Tea').last);
      await tester.pumpAndSettle();
      await fillRow(tester, 0, '250 g', '290', '250', '24', barcode: '8964000000250');
      await tapKey(tester, 'pack-add-row');
      await fillRow(tester, 1, '400 g', '450', '400', '5');
      await tapKey(tester, 'pack-add-row');
      await fillRow(tester, 2, '500 g', '550', '500', '18', barcode: '8964000000500');
      await tapKey(tester, 'pack-add-row');
      await fillRow(tester, 3, '1 kg', '1050', '950', '8');
      // Remove the draft 400 g size.
      await tapKey(tester, 'pack-row-1-remove');
    }

    testWidgets('creates a family of three sizes with whole-pack stock', (tester) async {
      CustomProductDraft? draft;
      await openDialog(tester, const CustomProductDialog(categories: [ProductCategory(id: 'tea', name: 'Tea')], ids: _CountingIds()),
          (d) => draft = d);
      await fillFamily(tester);
      await tapKey(tester, 'custom-product-create');
      final family = draft!.family!;
      expect((family.name, family.categoryId), ('Tapal Danedar', 'tea'));
      expect(family.variants.map((v) => (v.packLabel, v.salePriceMinor, v.purchasePriceMinor, v.openingQuantity, v.lowStockLevel, v.barcode)), [
        ('250 g', 29000, 25000, 24000, 2000, '8964000000250'),
        ('500 g', 55000, 50000, 18000, 2000, '8964000000500'),
        ('1 kg', 105000, 95000, 8000, 2000, null),
      ]);
      expect(family.variants.map((v) => v.productId).toSet(), hasLength(3), reason: 'distinct ids');
      expect((draft!.input.familyId, draft!.input.unit), (family.familyId, ProductUnit.pack));
    });

    testWidgets('validation errors stay in the dialog', (tester) async {
      CustomProductDraft? draft;
      await openDialog(tester,
          const CustomProductDialog(categories: [ProductCategory(id: 'tea', name: 'Tea')], existingBarcodes: {'8964000000500'}),
          (d) => draft = d);
      await fillFamily(tester);
      await tapKey(tester, 'custom-product-create');
      expect(find.text('Barcode 8964000000500 is already used in this shop'), findsOneWidget);
      // After removing the 400 g draft: row 1 is 500 g, row 2 is 1 kg.
      await fill(tester, 'pack-row-1-barcode', '');
      await fill(tester, 'pack-row-2-label', '500G');
      await tapKey(tester, 'custom-product-create');
      expect(find.text('Pack size 500G is listed twice'), findsOneWidget, reason: 'case and spaces ignored');
      await fill(tester, 'pack-row-2-label', '1 kg');
      await fill(tester, 'pack-row-2-opening', '');
      await fill(tester, 'pack-row-2-sale', '0');
      await tapKey(tester, 'custom-product-create');
      expect(find.text('Enter a sale price for 1 kg'), findsOneWidget);
      expect(draft, isNull);
    });

    testWidgets('a partial failure locks the saved size and the retry re-sends the same ids', (tester) async {
      final attempts = <List<(String, String)>>[];
      CustomProductDraft? draft;
      await openDialog(
        tester,
        CustomProductDialog(
          categories: const [ProductCategory(id: 'tea', name: 'Tea')],
          ids: const _CountingIds(),
          onSubmit: (submitted) async {
            final family = submitted.family!;
            attempts.add([for (final v in family.variants) (v.productId, v.movementId)]);
            if (attempts.length == 1) {
              throw FamilyCreationIncomplete(
                created: [family.variants.first.productId], failedLabel: '500 g', reason: 'network down');
            }
          },
        ),
        (d) => draft = d,
      );
      await fillFamily(tester);
      await tapKey(tester, 'custom-product-create');
      expect(find.textContaining('Pack 500 g was not created: network down'), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-row-0-saved')), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('pack-row-0-remove'))).onPressed, isNull,
          reason: 'a saved size cannot be removed');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('pack-row-0-label'))).readOnly, isTrue);
      await tapKey(tester, 'custom-product-create');
      expect(attempts, hasLength(2));
      expect(attempts[1], attempts[0], reason: 'same product and movement ids on retry');
      expect(draft, isNotNull);
    });

    testWidgets('single piece and loose forms are unchanged', (tester) async {
      await openDialog(tester, const CustomProductDialog(categories: [ProductCategory(id: 'tea', name: 'Tea')]), (_) {});
      expect(find.text('Pack size / label'), findsOneWidget);
      expect(find.byKey(const ValueKey('custom-product-packs')), findsNothing);
      await tapKey(tester, 'selling-loose');
      expect(find.byKey(const ValueKey('custom-product-presets')), findsOneWidget);
      expect(find.byKey(const ValueKey('custom-product-packs')), findsNothing);
    });
  });

  group('cashier POS', () {
    Future<AppDatabase> pumpPos(WidgetTester tester, {bool allowNegativeStock = true}) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(MaterialApp(
        home: PosWorkspace(
          shopName: 'ALI Shop',
          cashierName: 'ahmed1',
          initialCatalog: PosCatalogSnapshot(
            products: [_surf, _t250, _t500, _t1kg, _atta],
            categories: const [],
            customers: const [],
            allowNegativeStock: allowNegativeStock,
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

    final familyCard = find.byKey(const ValueKey('family-card-tapal'));
    final bill = find.byKey(const ValueKey('current-bill-panel'));

    Future<void> pick(WidgetTester tester, String id) async {
      await tester.tap(find.descendant(of: familyCard, matching: find.text('Add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('pack-pick-$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('one grouped card; the selector shows each size, price and stock', (tester) async {
      final db = await pumpPos(tester);
      expect(familyCard, findsOneWidget);
      expect(find.descendant(of: familyCard, matching: find.text('Tapal Danedar')), findsOneWidget);
      expect(find.descendant(of: familyCard, matching: find.text('3 pack sizes')), findsOneWidget);
      expect(find.descendant(of: familyCard, matching: find.text('From Rs 290.00')), findsOneWidget);
      expect(find.byType(PosProductCard), findsNWidgets(2), reason: 'Surf and Atta stay single cards');
      await tester.tap(find.descendant(of: familyCard, matching: find.text('Add')));
      await tester.pumpAndSettle();
      for (final (id, label, info) in [
        ('t250', '250 g', 'Rs 290.00 • 24 packs'),
        ('t500', '500 g', 'Rs 550.00 • 18 packs'),
        ('t1kg', '1 kg', 'Rs 1050.00 • 8 packs'),
      ]) {
        expect(find.text(label), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(ValueKey('pack-info-$id'))).data, info);
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: bill, matching: find.textContaining('Tapal')), findsNothing);
      await disposePos(tester, db);
    });

    testWidgets('one pack per pick; same size merges; sizes stay separate lines', (tester) async {
      final db = await pumpPos(tester);
      await pick(tester, 't500');
      expect(find.descendant(of: bill, matching: find.text('Tapal Danedar 500 g')), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-packs-t500')), findsOneWidget);
      expect(find.text('1 pack × Rs 550.00'), findsOneWidget);
      expect(find.byType(MeasuredQuantityPicker), findsNothing, reason: 'a pack is not loose tea');
      await pick(tester, 't500');
      expect(find.text('2 packs × Rs 550.00'), findsOneWidget);
      expect(find.descendant(of: bill, matching: find.text('Rs 1100.00')), findsWidgets);
      await pick(tester, 't250');
      expect(find.descendant(of: bill, matching: find.text('Tapal Danedar 250 g')), findsOneWidget);
      expect(find.text('1 pack × Rs 290.00'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget, reason: 'two lines, not merged');
      // The piece stepper still works on a pack line.
      final steppers = find.descendant(of: bill, matching: find.byIcon(Icons.add));
      expect(steppers, findsNWidgets(2));
      await tester.tap(steppers.first);
      await tester.pump();
      expect(find.text('3 packs × Rs 550.00'), findsOneWidget);
      await disposePos(tester, db);
    });

    testWidgets('search: name shows the family, a size shows that pack, barcode adds it', (tester) async {
      final db = await pumpPos(tester);
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Danedar');
      await tester.pump();
      expect(familyCard, findsOneWidget);
      await tester.enterText(searchField, '500g');
      await tester.pump();
      expect(familyCard, findsNothing);
      expect(find.descendant(of: find.byType(PosProductCard), matching: find.text('Tapal Danedar 500 g')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(PosProductCard), matching: find.text('Add')));
      await tester.pump();
      expect(find.text('1 pack × Rs 550.00'), findsOneWidget, reason: 'direct add of the exact size');
      await tester.enterText(searchField, '8964000001000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.descendant(of: bill, matching: find.text('Tapal Danedar 1 kg')), findsOneWidget);
      await disposePos(tester, db);
    });

    testWidgets('without negative stock, an empty size cannot be added', (tester) async {
      final db = await pumpPos(tester, allowNegativeStock: false);
      for (var i = 0; i < 8; i++) {
        await pick(tester, 't1kg');
      }
      await tester.tap(find.descendant(of: familyCard, matching: find.text('Add')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('pack-pick-t1kg'))).onPressed, isNull);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('pack-pick-t500'))).onPressed, isNotNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await disposePos(tester, db);
    });

    testWidgets('legacy piece and U2 loose products behave as before', (tester) async {
      final db = await pumpPos(tester);
      await tester.tap(find.descendant(
          of: find.ancestor(of: find.text('Surf'), matching: find.byType(PosProductCard)), matching: find.text('Add')));
      await tester.pump();
      expect(find.descendant(of: bill, matching: find.text('Surf')), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-packs-surf')), findsNothing);
      await tester.tap(find.descendant(
          of: find.ancestor(of: find.text('Atta'), matching: find.byType(PosProductCard)), matching: find.text('Add')));
      await tester.pumpAndSettle();
      expect(find.byType(MeasuredQuantityPicker), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await disposePos(tester, db);
    });
  });

  group('local sale, stock and snapshots', () {
    test('selling 500 g reduces only the 500 g stock; Bills keep the size name', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final at = DateTime.utc(2026, 10, 10, 6);
      await db.into(db.shops).insert(ShopsCompanion.insert(
        id: 'shop', name: 'S', phone: '', address: '', subscriptionPlan: SubscriptionPlan.trial,
        subscriptionStatus: SubscriptionStatus.trial, createdAt: at, updatedAt: at));
      await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
        id: 'm', shopId: 'shop', userId: 'owner', role: ShopRole.owner, createdAt: at));
      await db.into(db.devices).insert(DevicesCompanion.insert(
        id: 'd', shopId: 'shop', deviceName: 'd', deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: at));
      for (final (id, label, price, stock, barcode) in [
        ('t250', '250 g', 29000, 24000, '8964000000250'),
        ('t500', '500 g', 55000, 18000, '8964000000500'),
        ('t1kg', '1 kg', 105000, 8000, '8964000001000'),
      ]) {
        await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
          id: id, shopId: 'shop', customName: const Value('Tapal Danedar'), packLabel: Value(label),
          familyId: const Value('tapal'), unit: const Value('pack'), barcode: Value(barcode),
          purchasePrice: price - 4000, salePrice: price, createdAt: at, updatedAt: at));
        await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
          id: 'open-$id', shopId: 'shop', productId: id, type: InventoryMovementType.openingStock,
          quantity: stock, createdBy: 'owner', createdAt: at));
      }
      // The catalog groups them, resolves barcodes exactly and keeps sizes.
      final catalog = await DriftPosCatalog(db, shopId: 'shop').load();
      final entries = groupCatalog(catalog.products);
      expect((entries.single.isFamily, entries.single.name, entries.single.variants.length), (true, 'Tapal Danedar', 3));
      expect(catalog.products.firstWhere((p) => p.barcode == '8964000000500').id, 't500');

      final t500 = catalog.products.firstWhere((p) => p.id == 't500');
      final t250 = catalog.products.firstWhere((p) => p.id == 't250');
      final cart = PosCart()..add(t500)..add(t500)..add(t250);
      final sale = await LocalSaleService(db, const UuidV7Generator(), clock: () => at).createSale(SaleDraft(
        shopId: 'shop', cashierId: 'owner', deviceId: 'd', lines: cart.toSaleLines(),
        payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: cart.subtotalMinor)]));
      expect(sale.grandTotalMinor, 2 * 55000 + 29000);
      Future<int> stock(String id) async => (await db.customSelect(
              'select coalesce(sum(quantity),0) q from inventory_movements where product_id=?',
              variables: [Variable(id)]).getSingle())
          .read<int>('q');
      expect((await stock('t500'), await stock('t250'), await stock('t1kg')), (16000, 23000, 8000),
          reason: 'only the sold sizes move; no conversion between packs');

      final items = await (db.select(db.saleItems)..where((t) => t.saleId.equals(sale.saleId))).get();
      expect(items.map((i) => (i.productId, i.productNameSnapshot, i.quantity, i.lineTotal, i.measureUnitSnapshot)).toSet(), {
        ('t500', 'Tapal Danedar 500 g', 2000, 110000, null),
        ('t250', 'Tapal Danedar 250 g', 1000, 29000, null),
      });
      final history = DriftSalesHistoryRepository(db, shopId: 'shop');
      final row = (await history.page(
              filter: SaleHistoryFilter(range: ReportRange(DateTime.utc(2026), DateTime.utc(2027), label: 'all'))))
          .single;
      final receipt = (await history.detail(row)).toReceipt('S');
      expect(receipt.lines.map((l) => (l.name, l.quantity, l.total)).toSet(),
          {('Tapal Danedar 500 g', 2000, 110000), ('Tapal Danedar 250 g', 1000, 29000)});

      // The owner list names each size and finds it by pack size.
      final owner = DriftProductManagementRepository(db, shopId: 'shop');
      expect((await owner.products()).map((p) => (p.name, p.familyId)).toSet(), {
        ('Tapal Danedar 250 g', 'tapal'), ('Tapal Danedar 500 g', 'tapal'), ('Tapal Danedar 1 kg', 'tapal')});
      expect((await owner.products(query: '500g')).map((p) => p.id), ['t500']);
      expect((await owner.products(query: '8964000001000')).map((p) => p.id), ['t1kg']);
    });
  });
}

/// Mints predictable ids: id-1, id-2, ...
final class _CountingIds implements IdGenerator {
  const _CountingIds();
  static var _n = 0;
  @override
  String next() => 'id-${++_n}';
}

final class _NoIds implements IdGenerator {
  @override
  String next() => throw StateError('family ids come from the draft');
}

/// Behaves like create_shop_product: a repeated product id answers
/// already_exists and writes no second opening movement.
final class _IdempotentGateway implements ProductManagementGateway {
  final rows = <String, CustomProductInput>{};
  final movements = <String>[];
  String? failOnce;

  @override
  Future<String> createCustomProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required CustomProductInput input,
  }) async {
    if (failOnce == shopProductId) {
      failOnce = null;
      throw Exception('network down');
    }
    if (rows.containsKey(shopProductId)) return shopProductId;
    rows[shopProductId] = input;
    movements.add(movementId);
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
