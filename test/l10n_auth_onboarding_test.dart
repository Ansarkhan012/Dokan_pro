// Stage 2B Batch 6: sign-in, onboarding, device and cashier login, owner
// lock, subscription, sync reasons and web placeholders in Urdu.
//
// Domain and service code keeps its English messages (logs, tests, sync
// rows); the UI translates them. These tests prove that: every message the
// auth, device, subscription and sync layers can show has an Urdu
// translation and English stays byte-for-byte the same; a language switch
// keeps sign-in, owner-unlock and cashier-login state; a subscription refusal
// is still enforced (only its wording changes); and the screens fit at phone
// and tablet sizes with real fonts at text scale 1.0 and 1.3.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/app/auth_gate.dart';
import 'package:dukaan_pro/app/cashier_login_panel.dart';
import 'package:dukaan_pro/app/localized_app.dart';
import 'package:dukaan_pro/app/owner_access.dart';
import 'package:dukaan_pro/app/owner_cashier_setup_panel.dart';
import 'package:dukaan_pro/auth/auth_session_controller.dart';
import 'package:dukaan_pro/auth/owner_mode_lock.dart';
import 'package:dukaan_pro/auth/supabase_auth_repository.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/errors/safe_error_message.dart';
import 'package:dukaan_pro/core/l10n/bidi.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/locale_controller.dart';
import 'package:dukaan_pro/core/l10n/messages.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/customers/customer_models.dart';
import 'package:dukaan_pro/features/expenses/expense_management_web.dart'
    as expenses_web;
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/purchases/purchase_management_web.dart'
    as purchases_web;
import 'package:dukaan_pro/features/reports/owner_dashboard_web.dart'
    as dashboard_web;
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/features/shop/cashier_admin_gateway.dart';
import 'package:dukaan_pro/features/sync/sync_attention_native.dart';
import 'package:dukaan_pro/subscription/entitlement.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:dukaan_pro/subscription/entitlement_store.dart';
import 'package:dukaan_pro/subscription/entitlement_verifier.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:dukaan_pro/sync/sync_failure.dart';
import 'package:dukaan_pro/sync/sync_health.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show RSAPublicKey;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/real_fonts.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));

/// Arabic-script letters: the text really is Urdu.
final _urduScript = RegExp('[؀-ۿ]');

const _sizes = [Size(360, 800), Size(1024, 600), Size(1340, 800)];

String _name(Size size) => '${size.width.toInt()}x${size.height.toInt()}';

/// String literals passed as [argument] in a source file, e.g. the messages
/// a policy returns. Read from source so a new message cannot ship without a
/// translation.
List<String> _literals(String path, RegExp argument) => argument
    .allMatches(File(path).readAsStringSync())
    .map((m) => m.group(1)!)
    .toList();

void _expectTranslated(String english, {String? reason}) {
  expect(localizedMessage(_en, english), english, reason: reason ?? english);
  final urdu = localizedMessage(_ur, english);
  expect(urdu, isNot(english), reason: reason ?? english);
  expect(urdu, contains(_urduScript), reason: reason ?? english);
}

void main() {
  // Never used for a request: nothing in these tests reaches the network.
  final client = SupabaseClient(
    'http://127.0.0.1:1',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  tearDownAll(client.dispose);

  setUpAll(() async {
    expectRealFontsAvailable();
    await loadRealFonts();
  });

  group('messages from the auth, device and subscription layers', () {
    test('every subscription message the policy returns is translated', () {
      final messages = _literals(
        'lib/subscription/entitlement_policy.dart',
        RegExp(r"MutationDecision\.\w+,\s*'([^']+)'"),
      ).toSet();
      expect(messages.length, greaterThanOrEqualTo(7));
      messages.forEach(_expectTranslated);
      // The settings fallback uses the same text as the policy.
      expect(
        _literals(
          'lib/features/settings/owner_settings_screen.dart',
          RegExp(r"MutationDecision\.block,\s*'([^']+)'"),
        ).toSet(),
        everyElement(isIn(messages)),
      );
    });

    test('every device lobby warning is translated', () {
      final warnings = _literals(
        'lib/auth/device_mode.dart',
        RegExp(r"warning:\s*'([^']+)'"),
      );
      expect(warnings, hasLength(3));
      warnings.forEach(_expectTranslated);
    });

    test('sign-in errors are translated; server text is never shown', () {
      for (final message in _literals(
        'lib/core/errors/safe_error_message.dart',
        RegExp(r"return '([^']+)';"),
      )) {
        _expectTranslated(message);
      }
      final wrong = safeUserMessage(
        const AuthException('Invalid login credentials'),
        fallback: 'unused',
      );
      expect(wrong, 'Wrong email or password.');
      expect(localizedMessage(_ur, wrong), _ur.authErrWrongCredentials);
      // Registering a device keeps the exact English fallback.
      _expectTranslated(
        'Could not register this device. Check your connection.',
      );
    });

    test('every stored sync reason is translated; storage keeps English', () {
      final reasons = <String>{
        for (final error in <Object>[
          const AmbiguousTimestampPayload('sale.created_at', '2026-10-12'),
          TimeoutException('slow'),
          for (final code in [
            'DPV01',
            'DPC01',
            'DPX01',
            'DPA01',
            '42501',
            'PGRST301',
            'PGRST302',
            '401',
            '403',
            '40001',
            'XX999',
          ])
            PostgrestException(message: 'server text', code: code),
        ])
          classifySyncError(error).reason,
        ..._literals(
          'lib/database/repositories/sync_queue_repository.dart',
          RegExp(r"reason:\s*'([^']+)'"),
        ),
      };
      expect(reasons.length, greaterThanOrEqualTo(12));
      for (final reason in reasons) {
        expect(localizedSyncReason(_en, reason), reason);
        final urdu = localizedSyncReason(_ur, reason);
        expect(urdu, isNot(reason), reason: reason);
        expect(urdu, contains(_urduScript), reason: reason);
      }
      // Unknown text is shown as stored.
      expect(localizedSyncReason(_ur, 'Something new.'), 'Something new.');
    });

    test('a flagged reason translates known rules and keeps codes LTR', () {
      const stored =
          'Saved in the cloud, but it broke a shop rule '
          '(customer credit limit exceeded, odd_rule). Please review it.';
      expect(localizedSyncReason(_en, stored), stored);
      final urdu = localizedSyncReason(_ur, stored);
      expect(urdu, contains(_ur.syncFlagCreditLimit));
      expect(urdu, contains(isolateLtr('odd_rule')));
      expect(urdu, isNot(contains('customer credit limit exceeded')));
    });
  });

  group('subscription refusal is still enforced', () {
    test('the policy refuses with its unchanged English message', () async {
      final authorizer = EntitlementMutationAuthorizer(
        EntitlementPolicyService(
          verifier: EntitlementVerifier(
            RSAPublicKey(BigInt.from(3233), BigInt.from(17)),
          ),
          store: _EmptyEntitlementStore(),
        ),
      );
      Object? refused;
      try {
        await authorizer.authorize(shopId: 'shop', deviceId: 'device');
      } catch (error) {
        refused = error;
      }
      expect(refused, isA<SubscriptionMutationBlocked>());
      final message = (refused! as SubscriptionMutationBlocked).message;
      expect(message, 'Online subscription verification is required.');
      expect(localizedMessage(_ur, message), _ur.subMsgVerificationRequired);
    });

    for (final size in const [Size(360, 800), Size(1340, 800)]) {
      testWidgets('Urdu POS ${_name(size)}: banner translated, pay blocked', (
        tester,
      ) async {
        final committer = _Committer();
        await _pumpPos(
          tester,
          size,
          committer,
          const EntitlementEvaluation(
            EntitlementState.expired,
            MutationDecision.block,
            'Shop subscription needs renewal. Please contact the owner.',
          ),
        );
        expect(find.text(_ur.subMsgNeedsRenewal), findsOneWidget);
        expect(find.textContaining('renewal'), findsNothing);
        await tester.tap(find.textContaining('Surf Excel').first);
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('pay-button')).evaluate().isNotEmpty) {
          final pay = tester.widget<FilledButton>(
            find.byKey(const ValueKey('pay-button')),
          );
          expect(pay.onPressed, isNull);
        }
        expect(committer.completions, 0);
        expect(tester.takeException(), isNull);
        await _disposePos(tester);
      });
    }

    testWidgets('a warning (grace) is shown in Urdu and selling continues', (
      tester,
    ) async {
      final committer = _Committer();
      await _pumpPos(
        tester,
        const Size(1340, 800),
        committer,
        const EntitlementEvaluation(
          EntitlementState.offlineGrace,
          MutationDecision.allowWithStrongWarning,
          'Grace period active. Online verification is needed.',
        ),
      );
      expect(find.text(_ur.subMsgGrace), findsOneWidget);
      await tester.tap(find.textContaining('Surf Excel').first);
      await tester.pump(const Duration(milliseconds: 100));
      final pay = tester.widget<FilledButton>(
        find.byKey(const ValueKey('pay-button')),
      );
      expect(pay.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await _disposePos(tester);
    });

    // The cashier screen on a phone held upright: the top bar gives the
    // brand's room to the shop, sync status and cashier in both languages.
    for (final english in [false, true]) {
      for (final font in english ? [UrduFont.nastaliq] : UrduFont.values) {
        for (final scale in const [1.0, 1.3]) {
          for (final size in _sizes) {
            testWidgets('POS ${english ? 'English' : font.name} '
                '${_name(size)} text scale $scale fits', (tester) async {
              if (scale != 1.0) {
                tester.platformDispatcher.textScaleFactorTestValue = scale;
                addTearDown(
                  tester.platformDispatcher.clearTextScaleFactorTestValue,
                );
              }
              await _pumpPos(
                tester,
                size,
                _Committer(),
                const EntitlementEvaluation(
                  EntitlementState.expiringSoon,
                  MutationDecision.allowWithWarning,
                  'Subscription ending soon.',
                ),
                english: english,
                font: font,
              );
              expect(
                find.text(
                  english ? 'Subscription ending soon.' : _ur.subMsgEndingSoon,
                ),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              await _disposePos(tester);
            });
          }
        }
      }
    }

    testWidgets('English banner text is unchanged', (tester) async {
      await _pumpPos(
        tester,
        const Size(1340, 800),
        _Committer(),
        const EntitlementEvaluation(
          EntitlementState.expired,
          MutationDecision.block,
          'Shop subscription needs renewal. Please contact the owner.',
        ),
        english: true,
      );
      expect(
        find.text('Shop subscription needs renewal. Please contact the owner.'),
        findsOneWidget,
      );
      await _disposePos(tester);
    });
  });

  group('sign-in and onboarding screens in Urdu (real fonts)', () {
    for (final font in UrduFont.values) {
      for (final size in _sizes) {
        for (final scale in const [1.0, 1.3]) {
          testWidgets('${font.name} ${_name(size)} text scale $scale', (
            tester,
          ) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            if (scale != 1.0) {
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
            }
            final locale = LocaleController(
              initialLocale: LocaleController.urdu,
              initialUrduFont: font,
            );
            Future<void> show(Widget home) async {
              await tester.pumpWidget(
                LocalizedMaterialApp(
                  key: UniqueKey(),
                  controller: locale,
                  home: home,
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }

            // Owner sign-in: no sign-up, support contact instead.
            await show(_authForm(client, await _lock(locked: false)));
            expect(find.text(_ur.authOwnerSignIn), findsOneWidget);
            expect(find.text(_ur.authEmail), findsOneWidget);
            expect(find.text('Owner sign in'), findsNothing);
            for (final field in tester.widgetList<TextField>(
              find.byType(TextField),
            )) {
              // Email and password are typed left to right.
              expect(field.textDirection, TextDirection.ltr);
            }
            expect(find.text(_ur.authCreateOwnerAccount), findsNothing);
            expect(find.text(_ur.activationContactSupport), findsOneWidget);
            expect(find.text(_ur.authForgotPassword), findsOneWidget);
            expect(tester.takeException(), isNull);

            // Account without a shop: support provisions it.
            await show(NoShopPage(onSignOut: () async {}));
            expect(find.text(_ur.activationNoShopTitle), findsOneWidget);
            expect(find.text(_ur.activationContactSupport), findsOneWidget);
            expect(tester.takeException(), isNull);

            // Owner unlock prompt with a wrong password.
            final locked = await _lock(locked: true);
            await show(_hub(locked, _Reauth('secret')));
            expect(find.text(_ur.ownerLockedEnterPassword), findsOneWidget);
            await tester.enterText(
              find.byKey(const ValueKey('owner-unlock-password')),
              'wrong',
            );
            await tester.tap(find.text(_ur.ownerUnlock));
            await tester.pumpAndSettle();
            expect(find.text(_ur.ownerErrWrongPassword), findsOneWidget);
            expect(locked.ownerAccessAllowed, isFalse);
            expect(tester.takeException(), isNull);

            // An owner route opened while locked.
            await show(
              OwnerOnlyGuard(
                lock: locked,
                builder: (_) => const Text('OWNER SCREEN'),
              ),
            );
            expect(find.text(_ur.ownerAccessRequired), findsOneWidget);
            expect(find.text('OWNER SCREEN'), findsNothing);

            // Cashier login: an invalid PIN is refused in Urdu.
            await show(_lobby(client, _Cashiers(_twoCashiers)));
            expect(find.text(_ur.cashierStartShift), findsOneWidget);
            expect(find.text(_ur.cashierSelect), findsOneWidget);
            await _selectCashier(tester, 'احمد');
            await tester.enterText(find.byType(TextField), '12');
            await tester.tap(find.text(_ur.cashierStartShift));
            await tester.pumpAndSettle();
            expect(find.text(_ur.cashierErrPinFormat), findsOneWidget);
            expect(tester.takeException(), isNull);

            // No cashier yet, owner verified: first-cashier setup.
            await show(
              _lobby(client, _Cashiers(const []), allowManagement: true),
            );
            expect(find.text(_ur.cashierNoneCreated), findsOneWidget);
            await tester.tap(
              find.widgetWithText(FilledButton, _ur.cashierCreateFirst),
            );
            await tester.pumpAndSettle();
            expect(find.text(_ur.cashierNumericPin), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('English text of every screen is unchanged', (tester) async {
      Future<void> show(Widget home) async {
        await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: home));
        await tester.pumpAndSettle();
      }

      await show(_authForm(client, await _lock(locked: false)));
      for (final text in ['Owner sign in', 'Email', 'Password', 'Sign in']) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      for (final text in [
        'Forgot password?',
        'Contact Dokan Pro Support for Activation',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final text in ['Create owner account', 'Sign up', 'Full name']) {
        expect(find.text(text), findsNothing, reason: text);
      }

      await show(NoShopPage(onSignOut: () async {}));
      expect(find.text('No shop on this account'), findsOneWidget);

      final locked = await _lock(locked: true);
      await show(_hub(locked, _Reauth('secret')));
      await tester.enterText(
        find.byKey(const ValueKey('owner-unlock-password')),
        'wrong',
      );
      await tester.tap(find.text('Unlock owner mode'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong owner password.'), findsOneWidget);
      expect(
        find.text('Owner mode is locked. Enter the owner password.'),
        findsOneWidget,
      );

      await show(OwnerOnlyGuard(lock: locked, builder: (_) => const Text('x')));
      expect(find.text('Owner access required'), findsOneWidget);

      await show(_lobby(client, _Cashiers(_twoCashiers)));
      expect(find.text('Dukaan Pro — Ali Shop'), findsOneWidget);
      await _selectCashier(tester, 'Ahmed');
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Start Shift / Login'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter the cashier’s 4 to 8 digit PIN.'),
        findsOneWidget,
      );
    });
  });

  group('a language switch keeps sign-in and session state', () {
    testWidgets('owner sign-in form keeps typed email and its notice', (
      tester,
    ) async {
      final auth = SupabaseAuthRepository(client);
      final session = AuthSessionController(auth);
      final before = session.state;
      final locale = LocaleController();
      await tester.pumpWidget(
        LocalizedMaterialApp(
          controller: locale,
          home: AuthForm(
            auth: auth,
            session: session,
            ownerLock: await _lock(locked: false),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'owner@shop.pk');
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(AuthForm));

      await locale.setLocale(LocaleController.urdu);
      await tester.pumpAndSettle();
      expect(find.text(_ur.activationContactSupport), findsOneWidget);
      expect(find.text('owner@shop.pk'), findsOneWidget);
      expect(tester.state(find.byType(AuthForm)), same(state));
      expect(session.state, same(before));

      await locale.setLocale(LocaleController.english);
      await tester.pumpAndSettle();
      expect(find.text('owner@shop.pk'), findsOneWidget);
      expect(find.text('Contact Dokan Pro Support for Activation'), findsOne);
      session.dispose();
    });

    testWidgets('an unlocked owner stays unlocked; a shown error follows '
        'the language', (tester) async {
      final unlocked = await _lock(locked: false);
      final locale = LocaleController();
      await tester.pumpWidget(
        LocalizedMaterialApp(
          controller: locale,
          home: _hub(unlocked, _Reauth('secret')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Owner Dashboard'), findsOneWidget);
      await locale.setLocale(LocaleController.urdu);
      await tester.pumpAndSettle();
      expect(unlocked.ownerAccessAllowed, isTrue);
      // Action labels come from the hub (already localized there).
      expect(find.text('Owner Dashboard'), findsOneWidget);
      expect(find.text(_ur.ownerLockedEnterPassword), findsNothing);

      final locked = await _lock(locked: true);
      await locale.setLocale(LocaleController.english);
      await tester.pumpWidget(
        LocalizedMaterialApp(
          controller: locale,
          home: _hub(locked, _Reauth('secret')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('owner-unlock-password')),
        'wrong',
      );
      await tester.tap(find.text('Unlock owner mode'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong owner password.'), findsOneWidget);
      await locale.setLocale(LocaleController.urdu);
      await tester.pumpAndSettle();
      expect(find.text(_ur.ownerErrWrongPassword), findsOneWidget);
      expect(find.text('Wrong owner password.'), findsNothing);
      expect(locked.ownerAccessAllowed, isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('owner-unlock-password')),
        'secret',
      );
      await tester.tap(find.text(_ur.ownerUnlock));
      await tester.pumpAndSettle();
      expect(locked.ownerAccessAllowed, isTrue);
      expect(find.text('Owner Dashboard'), findsOneWidget);
    });

    testWidgets('cashier login keeps the selected cashier', (tester) async {
      final locale = LocaleController();
      await tester.pumpWidget(
        LocalizedMaterialApp(
          controller: locale,
          home: _lobby(client, _Cashiers(_twoCashiers)),
        ),
      );
      await tester.pumpAndSettle();
      await _selectCashier(tester, 'Ahmed');
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Start Shift / Login'));
      await tester.pumpAndSettle();
      await locale.setLocale(LocaleController.urdu);
      await tester.pumpAndSettle();
      expect(find.text(_ur.cashierErrPinFormat), findsOneWidget);
      expect(_selected(tester), 'c1');
      final login = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, _ur.cashierStartShift),
      );
      expect(login.onPressed, isNotNull);
    });
  });

  group('owner cashier setup', () {
    testWidgets('an Urdu name is saved exactly once and exactly as typed', (
      tester,
    ) async {
      final gateway = _Cashiers(const []);
      await tester.pumpWidget(
        LocalizedMaterialApp(
          controller: LocaleController(initialLocale: LocaleController.urdu),
          home: Scaffold(
            body: ListView(
              children: [
                OwnerCashierSetupPanel(
                  gateway: gateway,
                  shopId: 'shop',
                  cashiers: const [],
                  onChanged: () async {},
                  startWithCreateForm: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '  علی Ahmed  ');
      // Urdu keyboard digits are accepted as ASCII.
      await tester.enterText(fields.at(1), '۱۲۳۴');
      await tester.enterText(fields.at(2), '1234');
      final create = find.widgetWithText(FilledButton, _ur.cashierCreate);
      await tester.tap(create);
      await tester.tap(create, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(gateway.created, [('علی Ahmed', '1234')]);
      expect(tester.takeException(), isNull);
    });
  });

  group('sync issues show translated reasons', () {
    for (final urdu in [true, false]) {
      testWidgets(urdu ? 'Urdu' : 'English (stored text)', (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final reason = classifySyncError(
          const PostgrestException(message: 'server text', code: 'DPV01'),
        ).reason;
        await _seedAttention(db, reason);
        await tester.pumpWidget(
          LocalizedMaterialApp(
            controller: LocaleController(
              initialLocale: urdu
                  ? LocaleController.urdu
                  : LocaleController.english,
            ),
            home: Scaffold(
              body: SyncAttentionView(
                queue: SyncQueueRepository(db, shopId: 'shop'),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.textContaining(urdu ? _ur.syncReasonInvalid : reason),
          findsOneWidget,
        );
        if (urdu) expect(find.textContaining(reason), findsNothing);
        // The stored row is unchanged.
        final row = await db.select(db.syncOperations).getSingle();
        expect(row.attentionReason, reason);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 20));
        await db.close();
      });
    }
  });

  group('web placeholders', () {
    for (final urdu in [true, false]) {
      testWidgets(urdu ? 'Urdu' : 'English', (tester) async {
        final l10n = urdu ? _ur : _en;
        for (final (screen, title, body) in <(Widget, String, String)>[
          (
            expenses_web.ExpenseManagementScreen(
              client: client,
              shopId: 's',
              deviceId: 'd',
            ),
            l10n.ownerNavExpenses,
            l10n.expensesWebOnly,
          ),
          (
            purchases_web.PurchaseManagementScreen(
              client: client,
              shopId: 's',
              deviceId: 'd',
            ),
            l10n.ownerNavPurchases,
            l10n.purchasesWebOnly,
          ),
          (
            dashboard_web.OwnerDashboardScreen(
              client: client,
              shopId: 's',
              shopName: 'Ali Shop',
            ),
            urdu
                ? l10n.dashboardWebTitle(isolateAuto('Ali Shop'))
                : 'Ali Shop Dashboard',
            l10n.dashboardWebOnly,
          ),
        ]) {
          await tester.pumpWidget(
            LocalizedMaterialApp(
              key: UniqueKey(),
              controller: LocaleController(
                initialLocale: urdu
                    ? LocaleController.urdu
                    : LocaleController.english,
              ),
              home: screen,
            ),
          );
          expect(find.text(title), findsOneWidget);
          expect(find.text(body), findsOneWidget);
        }
        if (!urdu) {
          expect(_en.ownerNavExpenses, 'Expenses');
          expect(_en.ownerNavPurchases, 'Suppliers & Purchases');
          expect(
            _en.purchasesWebOnly,
            'Purchasing is available on Android and Windows.',
          );
        }
      });
    }
  });

  group('no untranslated UI text', () {
    test('no hard-coded user-visible literal in a widget text slot', () {
      // Text, labels, titles, hints, tooltips and messages must come from
      // the ARB files. Only these intentional literals remain.
      const allowed = {
        // Developer setup message (missing --dart-define); never shipped.
        'lib/app/dukaan_pro_app.dart',
        // Private platform admin panel (own entry point, operator-only,
        // English); never part of the shop app's UI.
        'lib/admin/admin_app.dart',
        'lib/admin/admin_main.dart',
        // The app name for the OS task switcher; a brand, not translated.
        'lib/app/localized_app.dart:Dukaan Pro',
        'lib/features/pos/pos_workspace.dart:Dukaan Pro',
        'lib/features/pos/pos_workspace.dart:DP',
        // Internal session states and report ranges: never rendered.
        'lib/auth/auth_session_controller.dart',
        'lib/features/reports/report_models.dart:Custom',
        'lib/features/sales/sales_history.dart:Sale',
        'lib/features/sales/sales_history.dart:Yesterday',
        // Domain text translated where it is shown (localizedMessage).
        'lib/features/receipts/receipt_printer.dart',
        // Paper widths, the same in both languages.
        'lib/features/settings/owner_settings_screen.dart:58 mm',
        'lib/features/settings/owner_settings_screen.dart:80 mm',
      };
      final slot = RegExp(
        r'''(?:\bText\(\s*|\b(?:labelText|hintText|helperText|errorText|tooltip|semanticLabel|semanticsLabel|title|message|label|content)\s*:\s*(?:const\s+)?(?:Text\(\s*)?)(['"])((?:(?!\1).)*)\1''',
        dotAll: true,
      );
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        final path = file.path.replaceAll(r'\', '/');
        if (file is! File ||
            !path.endsWith('.dart') ||
            path.endsWith('.g.dart') ||
            path.startsWith('lib/l10n/')) {
          continue;
        }
        final source = file.readAsStringSync();
        for (final match in slot.allMatches(source)) {
          final literal = match.group(2)!;
          // Only interpolations (`'${name}'`) are not text of their own.
          final text = literal.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), '');
          // A quote inside an interpolation ends the match early; what is
          // left is code, not text.
          if (text.contains(r'${')) continue;
          if (!RegExp('[A-Za-z]{2,}').hasMatch(text)) continue;
          if (allowed.contains(path) || allowed.contains('$path:$literal')) {
            continue;
          }
          offenders.add('$path: $literal');
        }
      }
      expect(offenders, isEmpty);
    });

    test('every Urdu string differs from English except intentional ones', () {
      // Language names, AM/PM-free formats and templates made only of
      // placeholders, and the brand heading are the same in both languages.
      const same = {
        'languageEnglish',
        'languageUrdu',
        'timeAm',
        'timePm',
        'measureQuantity',
        'receiptDateCashier',
        'receiptLine',
        'receiptAtPrice',
        'receiptPayment',
        'cashierLoginHeading',
      };
      final en = _arb('en'), ur = _arb('ur');
      final identical = [
        for (final key in en.keys)
          if (!key.startsWith('@') && en[key] == ur[key]) key,
      ];
      expect(identical.toSet(), same);
      expect(
        File('build/l10n_untranslated.txt').existsSync()
            ? File('build/l10n_untranslated.txt').readAsStringSync().trim()
            : '{}',
        anyOf('{}', ''),
      );
    });
  });
}

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Future<OwnerModeLock> _lock({required bool locked}) async {
  final lock = OwnerModeLock(_MemoryLockStore(locked: locked));
  await lock.load();
  return lock;
}

Widget _authForm(SupabaseClient client, OwnerModeLock lock) {
  final auth = SupabaseAuthRepository(client);
  return AuthForm(
    auth: auth,
    session: AuthSessionController(auth),
    ownerLock: lock,
  );
}

/// The owner hub as the app builds it: a page with the owner section.
Widget _hub(OwnerModeLock lock, OwnerReauthenticator reauthenticator) =>
    Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          OwnerModeSection(
            lock: lock,
            reauthenticator: reauthenticator,
            actions: [
              OwnerAction(
                label: 'Owner Dashboard',
                icon: Icons.analytics_outlined,
                primary: true,
                builder: (_) => const Scaffold(body: Text('NET PROFIT')),
              ),
            ],
          ),
        ],
      ),
    );

/// The device lobby layout: the cashier login panel in a narrow column.
Widget _lobby(
  SupabaseClient client,
  CashierAdminGateway directory, {
  bool allowManagement = false,
}) => Scaffold(
  appBar: AppBar(title: const Text('Ali Shop')),
  body: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ListView(
        padding: const EdgeInsets.all(24),
        shrinkWrap: true,
        children: [
          CashierLoginPanel(
            client: client,
            shopId: 'shop',
            shopName: 'Ali Shop',
            deviceIdentifier: 'identifier',
            directory: directory,
            allowManagement: allowManagement,
            onAuthenticated: (_, _) {},
          ),
        ],
      ),
    ),
  ),
);

const _twoCashiers = [
  CashierMetadata(id: 'c1', displayName: 'Ahmed', isActive: true),
  CashierMetadata(id: 'c2', displayName: 'احمد', isActive: true),
];

Future<void> _selectCashier(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(name).last);
  await tester.pumpAndSettle();
}

String? _selected(WidgetTester tester) => tester
    .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
    .value;

const _surf = PosProduct(
  id: 'surf',
  name: 'Surf Excel',
  salePriceMinor: 35000,
  stockQuantity: 9000,
  stockTrackingEnabled: true,
  barcode: '8964000000017',
  categoryId: 'household',
);

Future<void> _pumpPos(
  WidgetTester tester,
  Size size,
  _Committer committer,
  EntitlementEvaluation entitlement, {
  bool english = false,
  UrduFont font = UrduFont.nastaliq,
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
        shopName: 'Ali Shop',
        cashierName: 'Ahmed',
        initialCatalog: const PosCatalogSnapshot(
          products: [_surf],
          categories: [PosCategory(id: 'household', name: 'Household')],
          customers: [],
        ),
        committer: committer,
        salesHistory: DriftSalesHistoryRepository(db, shopId: 'shop'),
        offline: false,
        initialHasPendingSync: false,
        entitlement: entitlement,
        onLogout: () async {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

AppDatabase? _posDb;

Future<void> _disposePos(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(_posDb!.close);
}

Future<void> _seedAttention(AppDatabase db, String reason) async {
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
  await db
      .into(db.syncOperations)
      .insert(
        SyncOperationsCompanion.insert(
          id: 'op-1',
          shopId: 'shop',
          deviceId: 'device',
          entityType: 'expense',
          entityId: '0199c3a0-0000-7000-8000-000000000001',
          operationType: SyncOperationType.create,
          payload: '{}',
          status: const Value(SyncStatus.needsAttention),
          errorClass: const Value('permanent'),
          errorCode: const Value('DPV01'),
          attentionReason: Value(reason),
          retryCount: const Value(1),
          attentionAt: Value(at),
          createdAt: at,
          updatedAt: at,
        ),
      );
}

final class _Committer implements PosSaleCommitter {
  int completions = 0;
  @override
  Future<CreatedSale> complete(
    String checkoutId,
    PosCart cart,
    PosPaymentPlan payment,
  ) {
    completions++;
    throw UnimplementedError();
  }

  @override
  Future<PosCatalogSnapshot> reloadCatalog() => throw UnimplementedError();
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

final class _EmptyEntitlementStore implements EntitlementStore {
  @override
  Future<EntitlementRevocation?> readRevocation(String s, String d) async =>
      null;
  @override
  Future<void> writeRevocation(
    String s,
    String d,
    EntitlementRevocation? value,
  ) async {}
  @override
  Future<SignedEntitlement?> read(String shopId, String deviceId) async => null;
  @override
  Future<TrustedTimeObservation?> readTime(
    String shopId,
    String deviceId,
  ) async => null;
  @override
  Future<void> write(
    String shopId,
    String deviceId,
    SignedEntitlement token,
    TrustedTimeObservation time,
  ) async {}
}

final class _Cashiers implements CashierAdminGateway {
  _Cashiers(this.rows);
  final List<CashierMetadata> rows;
  final created = <(String, String)>[];
  @override
  Future<List<CashierMetadata>> cashiers({required String shopId}) async =>
      rows;
  @override
  Future<String> createCashier({
    required String shopId,
    required String displayName,
    required String pin,
  }) async {
    created.add((displayName, pin));
    return 'new-${created.length}';
  }

  @override
  Future<void> setActive({
    required String shopId,
    required String cashierId,
    required bool isActive,
  }) async {}
}

final class _Reauth implements OwnerReauthenticator {
  _Reauth(this.password);
  final String password;
  @override
  Future<bool> verifyPassword(String value) async => value == password;
}

final class _MemoryLockStore implements OwnerModeLockStore {
  _MemoryLockStore({this.locked = false});
  bool locked;
  @override
  Future<bool> read() async => locked;
  @override
  Future<void> write(bool value) async => locked = value;
}
