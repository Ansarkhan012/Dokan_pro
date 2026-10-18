// Full Edit Product, Adjust stock from Edit, and safe Delete (archive) with
// restore. Edits never write stock; a product is never removed (the server
// grants no delete), so "Delete" archives it: hidden from new sales, kept in
// old bills, stock history and reports, and restorable.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/app/owner_access.dart';
import 'package:dukaan_pro/auth/owner_mode_lock.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/inventory/drift_inventory_repository.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/products/drift_product_management_repository.dart';
import 'package:dukaan_pro/features/products/edit_product_dialog.dart';
import 'package:dukaan_pro/features/products/supabase_product_management_gateway.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));
final _t = DateTime.utc(2026, 10, 12, 6);

const _categories = [
  ProductCategory(id: 'cat-home', name: 'Household'),
  ProductCategory(id: 'cat-snacks', name: 'Snacks'),
];

const _surf = ManagedProduct(
  id: 'surf',
  name: 'Surf Excel',
  baseName: 'Surf Excel',
  categoryName: 'Household',
  categoryId: 'cat-home',
  barcode: '8964000000017',
  unit: 'piece',
  packLabel: '1 kg',
  purchasePriceMinor: 30000,
  salePriceMinor: 35000,
  stockQuantity: 12000,
  lowStockLevel: 2000,
  isActive: true,
  isCustom: true,
  movementCount: 3,
);

const _tapal250 = ManagedProduct(
  id: 'tapal-250',
  name: 'Tapal Danedar 250 g',
  baseName: 'Tapal Danedar',
  categoryName: 'Household',
  categoryId: 'cat-home',
  unit: 'pack',
  packLabel: '250 g',
  familyId: 'family-tapal',
  purchasePriceMinor: 38000,
  salePriceMinor: 41000,
  stockQuantity: 4000,
  lowStockLevel: 0,
  isActive: true,
  isCustom: true,
  movementCount: 1,
);

void main() {
  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('Edit Product form', () {
    testWidgets('opens with every current value', (tester) async {
      await _openEdit(tester, _surf, onSubmit: (_) async {});
      String text(String key) =>
          tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
      expect(text('edit-product-name'), 'Surf Excel');
      expect(text('edit-product-barcode'), '8964000000017');
      expect(text('edit-product-pack'), '1 kg');
      expect(text('edit-product-purchase'), '300');
      expect(text('edit-product-sale'), '350');
      expect(text('edit-product-low'), '2');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('edit-product-category')),
            )
            .initialValue,
        'cat-home',
      );
      expect(find.text(_en.posStock('12')), findsOneWidget);
      // Stock history exists: the unit is shown but fixed.
      expect(
        find.byKey(const ValueKey('edit-product-unit-fixed')),
        findsOneWidget,
      );
      expect(find.text(_en.editUnitLocked), findsOneWidget);
      expect(
        find.byKey(const ValueKey('edit-product-adjust-stock')),
        findsOneWidget,
      );
    });

    testWidgets('name, category and price changes are saved once; stock is '
        'never part of an edit', (tester) async {
      final edits = <ProductEdit>[];
      final result = await _openEdit(
        tester,
        _surf,
        onSubmit: (edit) async {
          edits.add(edit);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-name')),
        'Surf Excel Matic',
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-sale')),
        '375',
      );
      await tester.tap(find.byKey(const ValueKey('edit-product-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Snacks').last);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('edit-product-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(edits, hasLength(1));
      final edit = edits.single;
      expect(edit.name, 'Surf Excel Matic');
      expect(edit.categoryId, 'cat-snacks');
      expect(edit.salePriceMinor, 37500);
      expect(edit.purchasePriceMinor, 30000);
      expect(edit.barcodeChanged, isFalse);
      expect(edit.packLabelChanged, isFalse);
      expect(edit.unit, isNull);
      expect(await result(), isTrue);
    });

    testWidgets('a barcode used by another product is refused before sending', (
      tester,
    ) async {
      var calls = 0;
      await _openEdit(
        tester,
        _surf,
        barcodeOwners: {'8964000000017': 'surf', '1111': 'other-product'},
        onSubmit: (_) async => calls++,
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-barcode')),
        '1111',
      );
      final save = find.byKey(const ValueKey('edit-product-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(find.text(_en.prodErrBarcodeUsed('1111')), findsOneWidget);
      expect(calls, 0);
      // Its own barcode is fine.
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-barcode')),
        '8964000000017',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('a pack size keeps its family; a size label already in the '
        'family is refused', (tester) async {
      final edits = <ProductEdit>[];
      await _openEdit(
        tester,
        _tapal250,
        familySizes: ['500 g', '1 kg'],
        onSubmit: (edit) async => edits.add(edit),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-product-name')))
            .controller!
            .text,
        'Tapal Danedar',
      );
      expect(find.text(_en.editFamilyShared), findsOneWidget);
      // The family's shared name and category cannot be changed here: no
      // atomic server update for every size exists.
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-product-name')))
            .enabled,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('edit-product-category-fixed')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('edit-product-category')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-pack')),
        '500g',
      );
      final save = find.byKey(const ValueKey('edit-product-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(find.text(_en.prodErrPackTwice('500g')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-pack')),
        '250 gm',
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit-product-sale')),
        '420',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(edits.single.packLabel, '250 gm');
      expect(edits.single.packLabelChanged, isTrue);
      expect(edits.single.salePriceMinor, 42000);
      expect(edits.single.categoryId, isNull);
      expect(edits.single.name, isNull, reason: 'family name unchanged');
    });

    testWidgets('a refused save is explained and nothing closes', (
      tester,
    ) async {
      await _openEdit(
        tester,
        _surf,
        onSubmit: (_) async => throw const FormatException('offline'),
      );
      final save = find.byKey(const ValueKey('edit-product-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(_en.prodErrUpdateFailed), findsOneWidget);
      expect(find.byType(EditProductDialog), findsOneWidget);
    });

    testWidgets('Adjust stock shows the new recorded stock', (tester) async {
      var opened = 0;
      await _openEdit(
        tester,
        _surf,
        onSubmit: (_) async {},
        onAdjustStock: () async {
          opened++;
          return 32000;
        },
      );
      final adjust = find.byKey(const ValueKey('edit-product-adjust-stock'));
      await tester.ensureVisible(adjust);
      await tester.tap(adjust);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text(_en.posStock('32')), findsOneWidget);
    });

    for (final urdu in [false, true]) {
      for (final size in const [
        Size(1024, 600),
        Size(1340, 800),
        Size(400, 860),
      ]) {
        testWidgets('${urdu ? 'Urdu' : 'English'} ${size.width.toInt()}x'
            '${size.height.toInt()} with the keyboard open fits', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.45);
          addTearDown(tester.view.reset);
          final l10n = urdu ? _ur : _en;
          await _openEdit(
            tester,
            _surf,
            urdu: urdu,
            onSubmit: (_) async {},
            onAdjustStock: () async => null,
            onDelete: () async => false,
          );
          await tester.tap(find.byKey(const ValueKey('edit-product-name')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // Very little room: the dialog scrolls header, fields and buttons
          // together (PosFormDialog); each button can be reached and tapped.
          for (final key in ['edit-product-save', 'edit-product-archive']) {
            await tester.ensureVisible(find.byKey(ValueKey(key)));
            await tester.pumpAndSettle();
            expect(
              find.byKey(ValueKey(key)).hitTestable(),
              findsOneWidget,
              reason: key,
            );
          }
          expect(find.text(l10n.editArchive), findsOneWidget);
          await tester.ensureVisible(
            find.byKey(const ValueKey('edit-product-low')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Delete (archive) confirmation', () {
    testWidgets('the action and confirmation say Archive Product in both '
        'languages', (tester) async {
      await _openEdit(
        tester,
        _surf,
        onSubmit: (_) async {},
        onDelete: () async => false,
      );
      expect(find.text('Archive Product'), findsOneWidget);
      expect(find.textContaining('Delete'), findsNothing);
      await _openArchive(
        tester,
        usage: const ProductUsage(
          saleLines: 0,
          purchaseLines: 0,
          returnLines: 0,
          movements: 0,
        ),
        archive: () async {},
      );
      expect(find.text('Archive Surf Excel?'), findsOneWidget);
      expect(find.text('Archive Product'), findsOneWidget);
      expect(find.textContaining('delete', findRichText: true), findsNothing);
      await _openArchive(
        tester,
        urdu: true,
        usage: const ProductUsage(
          saleLines: 1,
          purchaseLines: 0,
          returnLines: 0,
          movements: 2,
        ),
        archive: () async {},
      );
      expect(find.text(_ur.archiveConfirm), findsOneWidget);
      expect(find.text(_ur.archiveHistoryExplain), findsOneWidget);
      expect(_ur.archiveConfirm, contains('آرکائیو'));
      for (final text in [
        _en.editArchive,
        _en.archiveConfirm,
        _en.archiveHistoryExplain,
        _en.archiveUnusedExplain,
      ]) {
        expect(text.toLowerCase(), isNot(contains('delete')), reason: text);
      }
    });

    testWidgets('a product with history is archived once, never deleted', (
      tester,
    ) async {
      var archives = 0;
      final result = await _openArchive(
        tester,
        usage: const ProductUsage(
          saleLines: 4,
          purchaseLines: 1,
          returnLines: 0,
          movements: 6,
        ),
        archive: () async {
          archives++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
      );
      expect(
        find.text(_en.archiveHistoryCounts('4', '1', '0', '6')),
        findsOneWidget,
      );
      expect(find.text(_en.archiveHistoryExplain), findsOneWidget);
      final confirm = find.byKey(const ValueKey('archive-confirm'));
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(archives, 1);
      expect(await result(), isTrue);
    });

    testWidgets('an unused product says it will be archived; a failure is '
        'explained (Urdu)', (tester) async {
      final result = await _openArchive(
        tester,
        urdu: true,
        usage: const ProductUsage(
          saleLines: 0,
          purchaseLines: 0,
          returnLines: 0,
          movements: 0,
        ),
        archive: () async => throw const FormatException('offline'),
      );
      expect(find.text(_ur.archiveUnusedExplain), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-usage')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('archive-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(_ur.archiveFailed), findsOneWidget);
      await tester.tap(find.text(_ur.commonCancel));
      await tester.pumpAndSettle();
      expect(await result(), isFalse);
    });

    testWidgets('owner screens stay closed while owner mode is locked', (
      tester,
    ) async {
      final lock = OwnerModeLock(_LockStore(locked: true));
      await lock.load();
      var built = false;
      await tester.pumpWidget(
        MaterialApp(
          home: OwnerOnlyGuard(
            lock: lock,
            builder: (_) {
              built = true;
              return const Text('PRODUCTS');
            },
          ),
        ),
      );
      expect(built, isFalse);
      expect(find.text('Owner access required'), findsOneWidget);
      expect(find.text(_en.editArchive), findsNothing);
    });
  });

  group('server edit is one request, whole or nothing', () {
    late List<http.Request> requests;
    late int status;
    late SupabaseProductManagementGateway gateway;
    setUp(() {
      requests = [];
      status = 204;
      gateway = SupabaseProductManagementGateway(
        SupabaseClient(
          'http://127.0.0.1:1',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              status == 204 ? '' : '{"message":"x"}',
              status,
              request: request,
            );
          }),
        ),
      );
    });

    const variantEdit = ProductEdit(
      purchasePriceMinor: 38000,
      salePriceMinor: 42000,
      lowStockLevel: 0,
      isActive: true,
      barcode: '777',
      barcodeChanged: true,
      packLabel: '250 gm',
      packLabelChanged: true,
    );

    test('a pack size price, barcode and label edit is one update of that '
        'size only', () async {
      await gateway.saveEdit(
        shopId: 'shop',
        product: _tapal250,
        edit: variantEdit,
      );
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.queryParameters['id'], 'eq.tapal-250');
      expect(request.url.queryParameters.containsKey('family_id'), isFalse);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['sale_price'], 42000);
      expect(body['barcode'], '777');
      expect(body['pack_label'], '250 gm');
      expect(body.containsKey('custom_name'), isFalse);
      expect(body.containsKey('category_id'), isFalse);
    });

    test('a shared family name or category is refused before anything is '
        'sent', () async {
      for (final edit in const [
        ProductEdit(
          purchasePriceMinor: 38000,
          salePriceMinor: 41000,
          lowStockLevel: 0,
          isActive: true,
          name: 'Tapal Tea',
        ),
        ProductEdit(
          purchasePriceMinor: 38000,
          salePriceMinor: 41000,
          lowStockLevel: 0,
          isActive: true,
          categoryId: 'cat-snacks',
        ),
      ]) {
        await expectLater(
          gateway.saveEdit(shopId: 'shop', product: _tapal250, edit: edit),
          throwsA(isA<UnsupportedError>()),
        );
      }
      expect(requests, isEmpty);
    });

    test(
      'a single product edit, name and category included, is one request',
      () async {
        await gateway.saveEdit(
          shopId: 'shop',
          product: _surf,
          edit: const ProductEdit(
            purchasePriceMinor: 30000,
            salePriceMinor: 36000,
            lowStockLevel: 2000,
            isActive: true,
            name: 'Surf Excel Matic',
            categoryId: 'cat-snacks',
          ),
        );
        expect(requests, hasLength(1));
        final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
        expect(body['custom_name'], 'Surf Excel Matic');
        expect(body['category_id'], 'cat-snacks');
      },
    );

    testWidgets('a refused server write never closes as saved', (tester) async {
      status = 500;
      final result = await _openEdit(
        tester,
        _tapal250,
        onSubmit: (edit) =>
            gateway.saveEdit(shopId: 'shop', product: _tapal250, edit: edit),
      );
      final save = find.byKey(const ValueKey('edit-product-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditProductDialog), findsOneWidget);
      expect(find.text(_en.prodErrUpdateFailed), findsOneWidget);
      expect(find.text(_en.productsSaved), findsNothing);
      await tester.tap(find.text(_en.commonCancel));
      await tester.pumpAndSettle();
      expect(await result(), isNull);
    });
  });

  group('local data after an edit or archive', () {
    late AppDatabase db;
    late DriftProductManagementRepository repo;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _seed(db);
      repo = DriftProductManagementRepository(db, shopId: 'shop');
    });
    tearDown(() => db.close());

    ManagedProduct byId(List<ManagedProduct> rows, String id) =>
        rows.singleWhere((p) => p.id == id);

    test('an accepted edit shows at once and never touches stock', () async {
      final before = byId(await repo.products(), 'surf');
      expect(before.stockQuantity, 10000);
      final movements = await db.select(db.inventoryMovements).get();
      await repo.applyAcceptedEdit(
        before,
        const ProductEdit(
          purchasePriceMinor: 31000,
          salePriceMinor: 37500,
          lowStockLevel: 1000,
          isActive: true,
          name: 'Surf Excel Matic',
          categoryId: 'cat-snacks',
          barcode: '555',
          barcodeChanged: true,
        ),
      );
      final after = byId(await repo.products(), 'surf');
      expect(after.name, 'Surf Excel Matic');
      expect(after.categoryId, 'cat-snacks');
      expect(after.barcode, '555');
      expect(after.salePriceMinor, 37500);
      expect(after.stockQuantity, 10000);
      expect(
        await db.select(db.inventoryMovements).get(),
        hasLength(movements.length),
      );
    });

    test('a pack size edit changes only that size; the family name is never '
        'changed locally', () async {
      final variant = byId(await repo.products(), 'tapal-250');
      await repo.applyAcceptedEdit(
        variant,
        const ProductEdit(
          purchasePriceMinor: 38000,
          salePriceMinor: 42000,
          lowStockLevel: 0,
          isActive: true,
          name: 'Tapal Danedar Tea',
        ),
      );
      final rows = await repo.products();
      expect(byId(rows, 'tapal-250').name, 'Tapal Danedar 250 g');
      expect(byId(rows, 'tapal-500').name, 'Tapal Danedar 500 g');
      expect(byId(rows, 'tapal-250').salePriceMinor, 42000);
      expect(byId(rows, 'tapal-500').salePriceMinor, 80000);
      expect(byId(rows, 'tapal-500').stockQuantity, 3000);
    });

    test('an unused product has no history', () async {
      final usage = await repo.usage('unused');
      expect(usage.hasHistory, isFalse);
    });

    test('an archived product leaves new sales but stays in bills, stock '
        'history and lists, and can be restored', () async {
      final sale = await _sell(db, 'surf', 2000);
      final usage = await repo.usage('surf');
      expect((usage.saleLines, usage.movements), (1, 2));
      expect(usage.hasHistory, isTrue);

      await repo.applyAcceptedActive('surf', false);

      // Not offered or accepted for a new sale.
      final catalog = await DriftPosCatalog(db, shopId: 'shop').load();
      expect(catalog.products.map((p) => p.id), isNot(contains('surf')));
      await expectLater(
        _sell(db, 'surf', 1000),
        throwsA(
          isA<SaleValidationException>().having(
            (e) => e.message,
            'message',
            'Product is not active for this shop',
          ),
        ),
      );
      // History is untouched and still names it.
      final history = DriftSalesHistoryRepository(db, shopId: 'shop');
      final detail = await history.detail((await history.sale(sale.saleId))!);
      expect(detail.lines.single.name, 'Surf Excel');
      final movements = await DriftInventoryRepository(
        db,
        shopId: 'shop',
      ).history();
      expect(
        movements.where((m) => m.productName == 'Surf Excel'),
        hasLength(2),
      );
      expect(await db.select(db.saleItems).get(), hasLength(1));
      // The owner finds it under Archived and can restore it.
      final archived = await repo.products(status: ProductListStatus.archived);
      expect(archived.map((p) => p.id), ['surf']);
      expect(
        (await repo.products(
          status: ProductListStatus.active,
        )).map((p) => p.id),
        isNot(contains('surf')),
      );
      await repo.applyAcceptedActive('surf', true);
      final restored = await DriftPosCatalog(db, shopId: 'shop').load();
      expect(restored.products.map((p) => p.id), contains('surf'));
      expect(byId(await repo.products(), 'surf').stockQuantity, 8000);
    });
  });
}

Future<Future<bool?> Function()> _openEdit(
  WidgetTester tester,
  ManagedProduct product, {
  required ProductEditSubmitter onSubmit,
  bool urdu = false,
  Map<String, String> barcodeOwners = const {},
  List<String> familySizes = const [],
  Future<int?> Function()? onAdjustStock,
  Future<bool> Function()? onDelete,
}) => _open(
  tester,
  urdu: urdu,
  builder: () => EditProductDialog(
    product: product,
    onSubmit: onSubmit,
    categories: _categories,
    barcodeOwners: barcodeOwners,
    familySizes: familySizes,
    onAdjustStock: onAdjustStock ?? () async => null,
    onDelete: onDelete,
  ),
);

Future<Future<bool?> Function()> _openArchive(
  WidgetTester tester, {
  required ProductUsage usage,
  required Future<void> Function() archive,
  bool urdu = false,
}) => _open(
  tester,
  urdu: urdu,
  builder: () => ArchiveProductDialog(
    product: _surf,
    usage: Future.value(usage),
    archive: archive,
  ),
);

Future<Future<bool?> Function()> _open(
  WidgetTester tester, {
  required Widget Function() builder,
  bool urdu = false,
}) async {
  late Future<bool?> result;
  await tester.pumpWidget(
    LocalizedMaterialApp(
      // A fresh navigator for each dialog opened in one test.
      key: UniqueKey(),
      controller: LocaleController(
        initialLocale: urdu ? LocaleController.urdu : LocaleController.english,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => result = showDialog<bool>(
                context: context,
                builder: (_) => builder(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<CreatedSale> _sell(AppDatabase db, String product, int quantity) async {
  final price = (await (db.select(
    db.shopProducts,
  )..where((t) => t.id.equals(product))).getSingle()).salePrice;
  return LocalSaleService(
    db,
    const UuidV7Generator(),
    clock: () => _t,
  ).createSale(
    SaleDraft(
      shopId: 'shop',
      cashierId: 'owner',
      deviceId: 'device',
      lines: [SaleLineDraft(productId: product, quantity: quantity)],
      payments: [
        SalePaymentDraft(
          method: PaymentMethod.cash,
          amountMinor: (price * quantity + 500) ~/ 1000,
        ),
      ],
    ),
  );
}

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.shops)
      .insert(
        ShopsCompanion.insert(
          id: 'shop',
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
      .into(db.shopUsers)
      .insert(
        ShopUsersCompanion.insert(
          id: 'm',
          shopId: 'shop',
          userId: 'owner',
          role: ShopRole.owner,
          createdAt: _t,
        ),
      );
  await db
      .into(db.devices)
      .insert(
        DevicesCompanion.insert(
          id: 'device',
          shopId: 'shop',
          deviceName: 'd',
          deviceType: DeviceType.androidTablet,
          deviceIdentifier: 'd',
          createdAt: _t,
        ),
      );
  for (final (id, name) in [
    ('cat-home', 'Household'),
    ('cat-snacks', 'Snacks'),
  ]) {
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            shopId: const Value('shop'),
            name: name,
            createdAt: _t,
            updatedAt: _t,
          ),
        );
  }
  for (final (id, name, label, family, price, stock) in [
    ('surf', 'Surf Excel', null, null, 35000, 10000),
    ('tapal-250', 'Tapal Danedar', '250 g', 'family-tapal', 41000, 4000),
    ('tapal-500', 'Tapal Danedar', '500 g', 'family-tapal', 80000, 3000),
    ('unused', 'Unused', null, null, 1000, 0),
  ]) {
    await db
        .into(db.shopProducts)
        .insert(
          ShopProductsCompanion.insert(
            id: id,
            shopId: 'shop',
            customName: Value(name),
            categoryId: const Value('cat-home'),
            packLabel: Value(label),
            familyId: Value(family),
            purchasePrice: price - 1000,
            salePrice: price,
            createdAt: _t,
            updatedAt: _t,
          ),
        );
    if (stock > 0) {
      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              id: 'open-$id',
              shopId: 'shop',
              productId: id,
              type: InventoryMovementType.openingStock,
              quantity: stock,
              createdBy: 'owner',
              createdAt: _t,
            ),
          );
    }
  }
}

final class _LockStore implements OwnerModeLockStore {
  _LockStore({required this.locked});
  bool locked;
  @override
  Future<bool> read() async => locked;
  @override
  Future<void> write(bool value) async => locked = value;
}
