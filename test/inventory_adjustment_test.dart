// Stock adjustments: `+20` and other signed or decimal quantities, the
// actual validation problem instead of a generic error, exactly one saved
// adjustment per Save, no failure message after a successful save (the
// upload is best effort), and a dialog that stays usable above the tablet's
// soft keyboard in English and Urdu.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/inventory/inventory_management_native.dart';
import 'package:dukaan_pro/features/inventory/inventory_models.dart';
import 'package:dukaan_pro/features/inventory/local_inventory_adjustment_service.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));
final _t = DateTime.utc(2026, 10, 12, 6);
const _shop = 'shop';
const _owner = 'owner-1';

const _surf = InventoryProductRow(
  id: 'surf',
  name: 'Surf Excel',
  unit: 'piece',
  stockQuantity: 5000,
  lowStockLevel: null,
  isActive: true,
);

void main() {
  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('typed quantity', () {
    test('+20, 20, -5, 2.5 and Urdu digits parse to thousandths', () {
      expect(parseSignedQuantity('+20'), 20000);
      expect(parseSignedQuantity(' + 20 '), 20000);
      expect(parseSignedQuantity('20'), 20000);
      expect(parseSignedQuantity('-5'), -5000);
      expect(parseSignedQuantity('−5'), -5000);
      expect(parseSignedQuantity('2.5'), 2500);
      expect(parseSignedQuantity('+۲۰'), 20000);
      for (final bad in ['', '+', 'abc', '2.5555', '--5', '1,000']) {
        expect(parseSignedQuantity(bad), isNull, reason: bad);
      }
    });

    test('each problem has its own message; a valid entry has none', () {
      String? problem(
        String quantity, {
        String note = 'Counted shelf',
        InventoryMovementType type = InventoryMovementType.manualAdjustment,
        bool measured = false,
      }) => adjustmentInputError(
        type: type,
        quantity: quantity,
        note: note,
        measured: measured,
      )?.call(_en);

      expect(problem('+20'), isNull);
      expect(problem('-5'), isNull);
      expect(problem('2.5', measured: true), isNull);
      expect(problem(''), _en.inventoryErrQuantityMissing);
      expect(problem('abc'), _en.inventoryErrQuantityFormat);
      expect(problem('0'), _en.inventoryErrQuantityZero);
      expect(problem('2.5'), _en.inventoryErrWholeUnits);
      expect(
        problem('-5', type: InventoryMovementType.damage),
        _en.inventoryErrQuantitySign,
      );
      expect(problem('+20', note: '  '), _en.inventoryErrReasonRequired);
      // Urdu has its own text for each.
      expect(
        adjustmentInputError(
          type: InventoryMovementType.manualAdjustment,
          quantity: '',
          note: '',
          measured: false,
        )!(_ur),
        _ur.inventoryErrQuantityMissing,
      );
      expect(
        _ur.inventoryErrQuantityMissing,
        isNot(_en.inventoryErrQuantityMissing),
      );
    });
  });

  group('adjustment service', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _seed(db);
    });
    tearDown(() => db.close());

    Future<String> record(InventoryMovementType type, int quantity) =>
        LocalInventoryAdjustmentService(
          db,
          const UuidV7Generator(),
          clock: () => _t,
        ).record(
          shopId: _shop,
          productId: 'surf',
          ownerId: _owner,
          deviceId: 'device',
          type: type,
          quantity: quantity,
          note: 'Counted shelf',
        );

    test('+20 is saved once with its audit and sync records', () async {
      await record(InventoryMovementType.manualAdjustment, 20000);
      expect(await _stock(db), 25000);
      final manual =
          await (db.select(db.inventoryMovements)..where(
                (t) =>
                    t.type.equalsValue(InventoryMovementType.manualAdjustment),
              ))
              .get();
      expect(manual.single.quantity, 20000);
      expect(await db.select(db.auditLogs).get(), hasLength(1));
      expect(await db.select(db.syncOperations).get(), hasLength(1));
    });

    test(
      'a decimal for a counted product is refused; nothing is written',
      () async {
        await expectLater(
          record(InventoryMovementType.manualAdjustment, 2500),
          throwsA(isA<ArgumentError>()),
        );
        expect(await _stock(db), 5000);
        expect(await db.select(db.syncOperations).get(), isEmpty);
      },
    );
  });

  group('adjustment dialog', () {
    for (final urdu in [false, true]) {
      final l10n = urdu ? _ur : _en;
      for (final size in const [
        Size(1024, 600),
        Size(1340, 800),
        Size(800, 1280),
      ]) {
        testWidgets('${urdu ? 'Urdu' : 'English'} ${size.width.toInt()}x'
            '${size.height.toInt()}: fits above the keyboard', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          // An Android soft keyboard taking about half a landscape tablet.
          tester.view.viewInsets = FakeViewPadding(bottom: size.height * 0.5);
          addTearDown(tester.view.reset);
          await _pumpDialog(tester, urdu: urdu, onSave: (_, _, _) async {});
          await tester.tap(find.byKey(const ValueKey('adjust-quantity')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // Cancel and Save stay on screen and can be tapped.
          for (final label in [
            l10n.commonCancel,
            l10n.inventorySaveAdjustment,
          ]) {
            final rect = tester.getRect(find.text(label));
            expect(
              rect.bottom,
              lessThanOrEqualTo(size.height * 0.5),
              reason: label,
            );
            expect(
              find.text(label).hitTestable(),
              findsOneWidget,
              reason: label,
            );
          }
          await tester.ensureVisible(find.byKey(const ValueKey('adjust-note')));
          expect(
            find.byKey(const ValueKey('adjust-note')).hitTestable(),
            findsOneWidget,
          );
        });
      }
    }

    testWidgets('+20 saves exactly once even with repeated taps', (
      tester,
    ) async {
      var calls = 0;
      final saves = <(InventoryMovementType, int, String)>[];
      final result = await _pumpDialog(
        tester,
        onSave: (type, quantity, note) async {
          calls++;
          saves.add((type, quantity, note));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('adjust-quantity')),
        '+20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('adjust-note')),
        ' Delivery ',
      );
      final save = find.byKey(const ValueKey('adjust-save'));
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(saves.single, (
        InventoryMovementType.manualAdjustment,
        20000,
        'Delivery',
      ));
      expect(await result(), isTrue);
      expect(find.text(_en.inventoryAdjustFailed), findsNothing);
    });

    testWidgets('invalid input shows the actual problem and saves nothing', (
      tester,
    ) async {
      var calls = 0;
      await _pumpDialog(tester, onSave: (_, _, _) async => calls++);
      final save = find.byKey(const ValueKey('adjust-save'));
      await tester.tap(save);
      await tester.pump();
      expect(find.text(_en.inventoryErrQuantityMissing), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('adjust-quantity')),
        '2.5',
      );
      await tester.tap(save);
      await tester.pump();
      expect(find.text(_en.inventoryErrWholeUnits), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('adjust-quantity')),
        '+20',
      );
      await tester.tap(save);
      await tester.pump();
      expect(find.text(_en.inventoryErrReasonRequired), findsOneWidget);
      expect(find.text(_en.inventoryErrInvalid), findsNothing);
      expect(calls, 0);
    });

    testWidgets('a refusal from the service is explained; the dialog stays', (
      tester,
    ) async {
      var calls = 0;
      final result = await _pumpDialog(
        tester,
        urdu: true,
        onSave: (_, _, _) async {
          calls++;
          throw StateError('This adjustment would make stock negative.');
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('adjust-quantity')),
        '-9',
      );
      await tester.enterText(find.byKey(const ValueKey('adjust-note')), 'گنتی');
      await tester.tap(find.byKey(const ValueKey('adjust-save')));
      await tester.pumpAndSettle();
      expect(find.text(_ur.inventoryErrWouldGoNegative), findsOneWidget);
      expect(find.byType(InventoryAdjustmentDialog), findsOneWidget);
      // Cancel closes it without a save.
      await tester.tap(find.text(_ur.commonCancel));
      await tester.pumpAndSettle();
      expect(await result(), isFalse);
      expect(calls, 1);
    });
  });

  testWidgets('screen: a saved +20 updates stock and history, with no false '
      'failure although the upload fails', (tester) async {
    tester.view.physicalSize = const Size(1340, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('inventory_adjust_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    // Never reaches a server: every upload fails, as offline.
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    // Not disposed, as in the owner screen tests (disposing it here stalled
    // the test run).
    await tester.runAsync(() async {
      final db = AppDatabase(
        NativeDatabase(File('${dir.path}/dukaan_pro.sqlite')),
      );
      await _seed(db);
      await db.close();
      String b64(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token':
              '${b64({'alg': 'HS256'})}.${b64({'sub': _owner, 'exp': 4102444800, 'role': 'authenticated'})}.x',
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
    await tester.pumpWidget(
      LocalizedMaterialApp(
        controller: LocaleController(),
        home: InventoryManagementScreen(
          client: client,
          shopId: _shop,
          deviceId: 'device',
          authorizer: const AllowFinancialMutations(),
        ),
      ),
    );
    await _settle(tester, until: find.text(_en.inventoryAdjust));
    await tester.tap(find.text(_en.inventoryAdjust));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('adjust-quantity')),
      '+20',
    );
    await tester.enterText(
      find.byKey(const ValueKey('adjust-note')),
      'Delivery',
    );
    await tester.tap(find.byKey(const ValueKey('adjust-save')));
    await tester.tap(
      find.byKey(const ValueKey('adjust-save')),
      warnIfMissed: false,
    );
    await _settle(tester, until: find.text(_en.inventoryAdjustSaved));
    expect(find.text(_en.inventoryAdjustSaved), findsOneWidget);
    expect(find.text(_en.inventoryAdjustFailed), findsNothing);
    expect(find.byType(InventoryAdjustmentDialog), findsNothing);
    // The list reloads with the new stock (5 + 20).
    await _settle(tester, until: find.text('25'));
    expect(find.text('25'), findsOneWidget);
    expect(find.text('5'), findsNothing);

    final rows = await tester.runAsync(() async {
      final db = AppDatabase(
        NativeDatabase(File('${dir.path}/dukaan_pro.sqlite')),
      );
      try {
        return (
          await (db.select(db.inventoryMovements)..where(
                (t) =>
                    t.type.equalsValue(InventoryMovementType.manualAdjustment),
              ))
              .get(),
          await _stock(db),
          await db.select(db.syncOperations).get(),
        );
      } finally {
        await db.close();
      }
    });
    expect(rows!.$1, hasLength(1), reason: 'saved exactly once');
    expect(rows.$1.single.quantity, 20000);
    expect(rows.$2, 25000);
    // Queued for upload; the failed attempt never removed it.
    expect(rows.$3, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  });
}

Future<Future<bool?> Function()> _pumpDialog(
  WidgetTester tester, {
  bool urdu = false,
  required Future<void> Function(InventoryMovementType, int, String) onSave,
}) async {
  late Future<bool?> result;
  await tester.pumpWidget(
    LocalizedMaterialApp(
      controller: LocaleController(
        initialLocale: urdu ? LocaleController.urdu : LocaleController.english,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => result = showDialog<bool>(
                context: context,
                builder: (_) =>
                    InventoryAdjustmentDialog(product: _surf, onSave: onSave),
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

/// Lets real database and failing network work finish between frames.
Future<void> _settle(WidgetTester tester, {Finder? until}) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (until != null && until.evaluate().isNotEmpty && i > 2) break;
    if (until == null && i > 6) break;
  }
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _seed(AppDatabase db) async {
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
  await db
      .into(db.shopProducts)
      .insert(
        ShopProductsCompanion.insert(
          id: 'surf',
          shopId: _shop,
          customName: const Value('Surf Excel'),
          purchasePrice: 30000,
          salePrice: 35000,
          createdAt: _t,
          updatedAt: _t,
        ),
      );
  await db
      .into(db.inventoryMovements)
      .insert(
        InventoryMovementsCompanion.insert(
          id: 'open-surf',
          shopId: _shop,
          productId: 'surf',
          type: InventoryMovementType.openingStock,
          quantity: 5000,
          createdBy: _owner,
          createdAt: _t,
        ),
      );
}

Future<int> _stock(AppDatabase db) async =>
    (await (db.select(
      db.inventoryMovements,
    )..where((t) => t.productId.equals('surf'))).get()).fold<int>(
      0,
      (sum, row) => sum + row.quantity,
    );
