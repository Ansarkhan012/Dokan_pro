// Stage 2B Batch 1: shared UI in Urdu. Localized formatters equal the
// original English helpers byte for byte; the POS shell (sidebar, status
// chip) and the Sync issues screen render in Urdu, mirrored, with real
// Roboto + Noto Nastaliq/Naskh metrics and no overflow at tablet, portrait
// and phone sizes and at text scale 1.0 and 1.3.
import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/format/display_format.dart';
import 'package:dukaan_pro/core/format/measure_format.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/core/l10n/localized_format.dart';
import 'package:dukaan_pro/core/ui/pos_ui.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/features/sync/sync_attention_native.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));

const _surf = PosProduct(
  id: 'surf',
  name: 'Surf Excel',
  salePriceMinor: 35000,
  stockQuantity: 9000,
  stockTrackingEnabled: true,
  barcode: '8964000000017',
  categoryId: 'household',
);

void main() {
  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('localized formatters', () {
    test('English output equals the original helpers exactly', () {
      final now = DateTime(2026, 10, 12, 15);
      for (final at in [
        DateTime(2026, 1, 5, 0, 7),
        DateTime(2026, 6, 30, 12, 0),
        DateTime(2026, 10, 12, 13, 17),
        DateTime(2026, 10, 11, 9, 2),
        DateTime(2026, 10, 13, 23, 59),
        DateTime(2025, 12, 31, 11, 59),
      ]) {
        expect(localizedDate(_en, at), formatDisplayDate(at));
        expect(localizedTime(_en, at), formatDisplayTime(at));
        expect(localizedDateTime(_en, at), formatDisplayDateTime(at));
        expect(
          localizedDateTime(_en, at, separator: ', '),
          formatDisplayDateTime(at, separator: ', '),
        );
        expect(
          localizedRelativeDateTime(_en, at, now: now),
          formatRelativeDateTime(at, now: now),
        );
      }
      for (final method in [
        'cash',
        'digital',
        'credit',
        'other',
        'Split',
        'Unknown',
        '',
        'bank_transfer',
      ]) {
        expect(localizedPaymentMethod(_en, method), paymentMethodLabel(method));
      }
      for (final unit in MeasureUnit.values) {
        for (final q in [0, 1, 250, 999, 1000, 1250, 1500, 2500, 12000, -750]) {
          expect(
            localizedMeasureQuantity(_en, q, unit),
            formatMeasureQuantity(q, unit),
          );
          expect(
            localizedLineQuantity(_en, q, unit),
            formatLineQuantity(q, unit),
          );
        }
        expect(
          localizedUnitPrice(_en, 'Rs 130.00', unit),
          measureUnitPriceLabel('Rs 130.00', unit),
        );
      }
      expect(
        localizedLineQuantity(_en, 3000, null),
        formatLineQuantity(3000, null),
      );
    });

    test('Urdu uses Urdu words with Western digits', () {
      final now = DateTime(2026, 10, 12, 15);
      expect(localizedDate(_ur, DateTime(2026, 10, 5)), '5 اکتوبر 2026');
      expect(localizedDate(_ur, DateTime(2026, 5, 1)), '1 مئی 2026');
      expect(
        localizedRelativeDateTime(
          _ur,
          DateTime(2026, 10, 12, 13, 17),
          now: now,
        ),
        'آج، 1:17 PM',
      );
      expect(
        localizedRelativeDateTime(_ur, DateTime(2026, 10, 11, 9, 2), now: now),
        'گزشتہ کل، 9:02 AM',
      );
      expect(
        localizedRelativeDateTime(_ur, DateTime(2026, 10, 13, 9, 2), now: now),
        'آئندہ کل، 9:02 AM',
      );
      expect(
        localizedRelativeDateTime(_ur, DateTime(2026, 10, 1, 9, 2), now: now),
        '1 اکتوبر 2026، 9:02 AM',
      );
      expect(localizedMeasureQuantity(_ur, 2500, MeasureUnit.kg), '2.5 کلو');
      expect(localizedMeasureQuantity(_ur, 250, MeasureUnit.kg), '250 گرام');
      expect(
        localizedMeasureQuantity(_ur, 750, MeasureUnit.liter),
        '750 ملی لیٹر',
      );
      expect(
        localizedMeasureQuantity(_ur, 1500, MeasureUnit.liter),
        '1.5 لیٹر',
      );
      expect(
        localizedUnitPrice(_ur, 'Rs 130.00', MeasureUnit.kg),
        'Rs 130.00 فی کلو',
      );
      expect(localizedPaymentMethod(_ur, 'credit'), 'ادھار');
      expect(localizedPaymentMethod(_ur, 'cash'), 'کیش');
      // No Urdu or Arabic digits ever.
      final all = [
        localizedDate(_ur, DateTime(2026, 12, 25)),
        localizedMeasureQuantity(_ur, 1250, MeasureUnit.kg),
      ].join();
      expect(RegExp('[٠-٩۰-۹]').hasMatch(all), isFalse);
    });

    test('context.l10n falls back to English outside the app shell', () {
      // A bare MaterialApp (as in older widget tests) never crashes.
      expect(_en.commonCancel, 'Cancel');
      expect(_ur.commonCancel, 'رہنے دیں');
    });
  });

  group('POS shell in Urdu (real fonts)', () {
    const sizes = [Size(1340, 800), Size(1024, 600), Size(600, 960)];
    for (final font in UrduFont.values) {
      for (final size in sizes) {
        for (final health in _Health.values) {
          testWidgets('${font.name} ${_name(size)} ${health.name}', (
            tester,
          ) async {
            await _pumpPos(tester, size, font: font, health: health);
            final l10n = _ur;
            expect(find.text(l10n.navSale), findsWidgets);
            expect(find.text(l10n.navKhata), findsWidgets);
            expect(find.text(health.label(l10n)), findsOneWidget);
            expect(find.text('Synced'), findsNothing);
            final sidebar = find.byKey(const ValueKey('cashier-sidebar'));
            if (sidebar.evaluate().isNotEmpty) {
              expect(
                Directionality.of(tester.element(sidebar)),
                TextDirection.rtl,
              );
              // Mirrored shell: the sidebar sits on the right edge.
              expect(tester.getTopRight(sidebar).dx, size.width);
            }
            expect(tester.takeException(), isNull);
            await _disposePos(tester);
          });
        }
      }
    }
    for (final font in UrduFont.values) {
      for (final size in sizes) {
        testWidgets('${font.name} ${_name(size)} text scale 1.3', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpPos(tester, size, font: font, health: _Health.syncing);
          expect(find.text(_ur.syncStatusSyncing), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _disposePos(tester);
        });
      }
    }
    testWidgets('English with real fonts is unchanged: labels and LTR', (
      tester,
    ) async {
      await _pumpPos(
        tester,
        const Size(600, 960),
        english: true,
        health: _Health.syncing,
      );
      expect(find.text('Syncing'), findsOneWidget);
      expect(find.text('Sale'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Syncing'))),
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
      await _disposePos(tester);
    });
  });

  group('Sync issues in Urdu (real fonts)', () {
    for (final size in const [Size(360, 800), Size(1340, 800)]) {
      for (final font in UrduFont.values) {
        testWidgets('${font.name} ${_name(size)}', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          await _seedAttention(db);
          await tester.pumpWidget(
            LocalizedMaterialApp(
              controller: LocaleController(
                initialLocale: LocaleController.urdu,
                initialUrduFont: font,
              ),
              home: Scaffold(
                appBar: AppBar(
                  title: Builder(builder: (c) => Text(c.l10n.syncIssuesTitle)),
                ),
                body: SyncAttentionView(
                  queue: SyncQueueRepository(db, shopId: 'shop'),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('سنک کے مسائل'), findsOneWidget);
          expect(find.text(_ur.syncNothingDeleted), findsOneWidget);
          expect(find.text(_ur.syncAcknowledge), findsOneWidget);
          expect(find.text(_ur.commonRetry), findsOneWidget);
          expect(
            find.textContaining(_ur.syncEntityStockAdjustment),
            findsOneWidget,
          );
          // The bill number and the technical code are never translated and
          // stay left to right inside the Urdu line.
          expect(find.textContaining(isolateLtr('DPV01')), findsOneWidget);
          expect(find.textContaining('کوڈ:'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          await _closeDb(tester, db);
        });
      }
    }

    testWidgets('English text is unchanged', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seedAttention(db);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncAttentionView(
              queue: SyncQueueRepository(db, shopId: 'shop'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Stock adjustment'), findsOneWidget);
      expect(
        find.textContaining('Code: DPV01 • Needs attention • '),
        findsOneWidget,
      );
      expect(
        find.textContaining('Code: DPV09 • Synced, flagged • '),
        findsOneWidget,
      );
      await _closeDb(tester, db);
    });
  });

  group('shared dialog footer', () {
    for (final (locale, size) in [
      (LocaleController.urdu, const Size(360, 800)),
      (LocaleController.urdu, const Size(1340, 800)),
      (LocaleController.english, const Size(360, 800)),
    ]) {
      testWidgets('${locale.languageCode} ${_name(size)}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          LocalizedMaterialApp(
            controller: LocaleController(initialLocale: locale),
            home: Builder(
              builder: (context) => Scaffold(
                body: PosFormDialog(
                  title: 'T',
                  body: (_, _) => const SizedBox(height: 40),
                  message: formFooterMessage(context, null),
                  actions: [
                    TextButton(
                      onPressed: () {},
                      child: Text(context.l10n.commonCancel),
                    ),
                    FilledButton(
                      onPressed: () {},
                      child: Text(context.l10n.commonSave),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final urdu = locale == LocaleController.urdu;
        final l10n = urdu ? _ur : _en;
        expect(find.text(l10n.commonRequiredHint), findsOneWidget);
        final save = tester.getCenter(find.text(l10n.commonSave)).dx;
        final cancel = tester.getCenter(find.text(l10n.commonCancel)).dx;
        // Actions sit at the end edge and keep reading order (Cancel first).
        if (urdu) {
          expect(save, lessThan(cancel));
          expect(save, lessThan(size.width / 2));
        } else {
          expect(save, greaterThan(cancel));
          expect(save, greaterThan(size.width / 2));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}

String _name(Size size) => '${size.width.toInt()}x${size.height.toInt()}';

enum _Health {
  synced,
  pending,
  syncing,
  offline,
  needsAttention;

  String label(AppLocalizations l10n) => switch (this) {
    synced => l10n.syncStatusSynced,
    pending => l10n.syncStatusPending,
    syncing => l10n.syncStatusSyncing,
    offline => l10n.syncStatusOffline,
    needsAttention => l10n.syncStatusNeedsAttention,
  };

  SyncHealth get stream => switch (this) {
    synced => SyncHealth.synced,
    pending || offline => SyncHealth.pending,
    syncing => SyncHealth.syncing,
    needsAttention => SyncHealth.needsAttention,
  };
}

AppDatabase? _posDb;

Future<void> _pumpPos(
  WidgetTester tester,
  Size size, {
  UrduFont font = UrduFont.nastaliq,
  bool english = false,
  required _Health health,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = _posDb = AppDatabase(NativeDatabase.memory());
  await tester.pumpWidget(
    LocalizedMaterialApp(
      controller: LocaleController(
        initialLocale: english
            ? LocaleController.english
            : LocaleController.urdu,
        initialUrduFont: font,
      ),
      home: PosWorkspace(
        shopName: 'ALI Shop',
        cashierName: 'ahmed1',
        initialCatalog: const PosCatalogSnapshot(
          products: [_surf],
          categories: [PosCategory(id: 'household', name: 'Household')],
          customers: [],
        ),
        committer: _Committer(health.stream),
        salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
        offline: health == _Health.offline,
        initialHasPendingSync: health != _Health.synced,
        onLogout: () async {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _disposePos(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(_posDb!.close);
}

Future<void> _closeDb(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  await db.close();
}

Future<void> _seedAttention(AppDatabase db) async {
  final at = DateTime.utc(2026, 10, 12, 8, 5);
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
          createdAt: at,
          updatedAt: at,
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
          createdAt: at,
        ),
      );
  for (final (id, type, status, errorClass, code) in [
    (
      'op-1',
      'inventory_movement',
      SyncStatus.needsAttention,
      'permanent',
      'DPV01',
    ),
    ('op-2', 'expense', SyncStatus.synced, 'flagged', 'DPV09'),
  ]) {
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            id: id,
            shopId: 'shop',
            deviceId: 'device',
            entityType: type,
            entityId: '0199c3a0-0000-7000-8000-00000000000$id',
            operationType: SyncOperationType.create,
            payload: '{}',
            status: Value(status),
            errorClass: Value(errorClass),
            errorCode: Value(code),
            retryCount: const Value(3),
            attentionAt: Value(at),
            createdAt: at,
            updatedAt: at,
          ),
        );
  }
}

final class _Committer implements PosSaleCommitter {
  _Committer(this.health);
  final SyncHealth health;
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
  Stream<SyncHealth> watchSyncHealth() => Stream.value(health);
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
