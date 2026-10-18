// B-4 (PROJECT_AUDIT.md §0.12): the POS fetches other devices' changes on
// resume and when connectivity returns, never overlapping and never more
// often than the minimum interval; the catalog reloads afterwards and changed
// cart prices are shown before payment. Real-server proof:
// test_r1/http/remote_refresh_http_test.dart.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/pull/remote_refresh.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteRefresh guard', () {
    late DateTime now;
    late int pulls;
    late bool online;
    Completer<bool>? gate;
    RemoteRefresh refresh() => RemoteRefresh(
      pull: () async {
        pulls++;
        if (gate case final g?) return g.future;
        return online;
      },
      minInterval: const Duration(seconds: 30),
      clock: () => now,
    );
    setUp(() {
      now = DateTime.utc(2026, 10, 13, 9);
      pulls = 0;
      online = true;
      gate = null;
    });

    test('overlapping triggers share one pull', () async {
      final r = refresh();
      gate = Completer<bool>();
      final a = r.onResume();
      final b = r.now();
      final c = r.onResume();
      gate!.complete(true);
      expect(await Future.wait([a, b, c]), [true, true, true]);
      expect(pulls, 1);
    });

    test('resume is throttled to the minimum interval', () async {
      final r = refresh();
      expect(await r.onResume(), isTrue);
      now = now.add(const Duration(seconds: 10));
      expect(await r.onResume(), isFalse);
      expect(pulls, 1);
      now = now.add(const Duration(seconds: 25));
      expect(await r.onResume(), isTrue);
      expect(pulls, 2);
    });

    test('ticks pull only while waiting for connectivity', () async {
      final r = refresh();
      expect(await r.onResume(), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(await r.onTick(), isFalse, reason: 'online and idle');
      expect(pulls, 1);

      online = false;
      now = now.add(const Duration(minutes: 2));
      expect(await r.onResume(), isFalse);
      expect(r.waitingForConnectivity, isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(await r.onTick(), isFalse, reason: 'still offline');
      online = true;
      now = now.add(const Duration(minutes: 2));
      expect(await r.onTick(), isTrue, reason: 'connectivity returned');
      expect(r.waitingForConnectivity, isFalse);
      expect(pulls, 4);
    });

    test('a successful upload after failed pulls pulls at once', () async {
      final r = refresh();
      online = false;
      expect(await r.onResume(), isFalse);
      online = true;
      now = now.add(const Duration(seconds: 1)); // inside the interval
      expect(await r.onUploadSucceeded(), isTrue);
      expect(await r.onUploadSucceeded(), isFalse, reason: 'not waiting any more');
      expect(pulls, 2);
    });

    test('a pull that throws is a failed pull, never an error', () async {
      final r = RemoteRefresh(pull: () async => throw StateError('boom'));
      expect(await r.onResume(), isFalse);
      expect(r.waitingForConnectivity, isTrue);
    });
  });

  group('POS screen', () {
    const surf = PosProduct(
      id: 'surf', name: 'Surf', salePriceMinor: 35000,
      stockQuantity: 10000, stockTrackingEnabled: true,
    );
    const surfNew = PosProduct(
      id: 'surf', name: 'Surf', salePriceMinor: 40000,
      stockQuantity: 10000, stockTrackingEnabled: true,
    );

    Future<(_Committer, AppDatabase)> pump(
      WidgetTester tester, {
      required RemoteRefresh remote,
      bool urdu = false,
    }) async {
      tester.view.physicalSize = const Size(1340, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      final committer = _Committer();
      await tester.pumpWidget(LocalizedMaterialApp(
        controller: LocaleController(
          initialLocale: urdu ? LocaleController.urdu : LocaleController.english,
        ),
        home: PosWorkspace(
          shopName: 'Ali Shop',
          cashierName: 'Ahmed',
          initialCatalog: const PosCatalogSnapshot(
            products: [surf], categories: [], customers: [],
          ),
          committer: committer,
          salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
          offline: false,
          initialHasPendingSync: false,
          onLogout: () async {},
          remoteRefresh: remote,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      return (committer, db);
    }

    Future<void> resume(WidgetTester tester) async {
      // The order Android reports: to the background and back.
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    Future<void> dispose(WidgetTester tester, AppDatabase db) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(db.close);
    }

    for (final urdu in [false, true]) {
      testWidgets('${urdu ? 'Urdu' : 'English'}: resume pulls, reloads and '
          'shows the changed price before payment', (tester) async {
        final l10n = lookupAppLocalizations(Locale(urdu ? 'ur' : 'en'));
        var pulls = 0;
        final (committer, db) = await pump(
          tester,
          urdu: urdu,
          remote: RemoteRefresh(pull: () async {
            pulls++;
            return true; // the owner's new price was pulled
          }),
        );
        committer.next = const PosCatalogSnapshot(
          products: [surfNew], categories: [], customers: [],
        );
        await tester.tap(find.textContaining('Surf').first);
        await tester.pump();
        expect(find.byKey(const ValueKey('cart-price-changes')), findsNothing);

        await resume(tester);
        expect(pulls, 1);
        expect(committer.reloads, 1);
        final line = l10n.posPriceChangeLine(
          urdu ? isolateAuto('Surf') : 'Surf',
          urdu ? isolateLtr('Rs 350.00') : 'Rs 350.00',
          urdu ? isolateLtr('Rs 400.00') : 'Rs 400.00',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('cart-price-changes')),
            matching: find.text(line),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('pay-button')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('payment-price-changes')),
            matching: find.text(line),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await dispose(tester, db);
      });
    }

    testWidgets('offline resume keeps the cached catalog and cart', (
      tester,
    ) async {
      final (committer, db) = await pump(
        tester,
        remote: RemoteRefresh(pull: () async => false),
      );
      committer.next = const PosCatalogSnapshot(
        products: [surfNew], categories: [], customers: [],
      );
      await tester.tap(find.textContaining('Surf').first);
      await tester.pump();
      await resume(tester);
      expect(committer.reloads, 0, reason: 'nothing pulled, nothing reloaded');
      expect(find.byKey(const ValueKey('cart-price-changes')), findsNothing);
      expect(find.textContaining('350.00'), findsWidgets);
      await dispose(tester, db);
    });

    testWidgets('a quick second resume does not pull again', (tester) async {
      var pulls = 0;
      final (_, db) = await pump(
        tester,
        remote: RemoteRefresh(pull: () async {
          pulls++;
          return true;
        }),
      );
      await resume(tester);
      await resume(tester);
      expect(pulls, 1);
      await dispose(tester, db);
    });
  });
}

final class _Committer implements PosSaleCommitter {
  var reloads = 0;
  PosCatalogSnapshot next = const PosCatalogSnapshot(
    products: [], categories: [], customers: [],
  );
  @override
  Future<CreatedSale> complete(
    String checkoutId,
    PosCart cart,
    PosPaymentPlan payment,
  ) => throw UnimplementedError();
  @override
  Future<PosCatalogSnapshot> reloadCatalog() async {
    reloads++;
    return next;
  }

  @override
  Future<bool> triggerSync() async => false;
  @override
  Stream<SyncHealth> watchSyncHealth() => Stream.value(SyncHealth.synced);
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
