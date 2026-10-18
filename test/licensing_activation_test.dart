// Admin-provisioned shops, the two-device rule and licence enforcement on the
// device (migration 202610140001). Server rules are proven by
// supabase/tests_raw/platform_admin_licensing_security.sql; these tests prove
// the app side: no self-registration, device classification, signed offline
// entitlements (forged or copied ones refused), a server refusal on reconnect
// blocking billing until renewal, and the English/Urdu wording.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dukaan_pro/app/auth_gate.dart';
import 'package:dukaan_pro/auth/auth_repository.dart';
import 'package:dukaan_pro/auth/auth_session_controller.dart';
import 'package:dukaan_pro/auth/domain/auth_state.dart';
import 'package:dukaan_pro/auth/owner_mode_lock.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/messages.dart';
import 'package:dukaan_pro/features/shop/device_registration_gateway.dart';
import 'package:dukaan_pro/subscription/activation_status.dart';
import 'package:dukaan_pro/subscription/entitlement.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:dukaan_pro/subscription/entitlement_store.dart';
import 'package:dukaan_pro/subscription/entitlement_verifier.dart';
import 'package:dukaan_pro/subscription/supabase_entitlement_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ur = lookupAppLocalizations(const Locale('ur'));
final _urduScript = RegExp('[؀-ۿ]');

void main() {
  late AsymmetricKeyPair<PublicKey, PrivateKey> keys;
  late _Store store;
  late EntitlementPolicyService policy;
  final issued = DateTime.utc(2026, 10, 1);

  setUpAll(() {
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 7))));
    keys =
        (RSAKeyGenerator()..init(
              ParametersWithRandom(
                RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
                random,
              ),
            ))
            .generateKeyPair();
  });
  setUp(() {
    store = _Store();
    policy = EntitlementPolicyService(
      verifier: EntitlementVerifier(keys.publicKey as RSAPublicKey),
      store: store,
    );
  });

  Map<String, dynamic> payload({String device = 'tablet-1'}) => {
    'entitlement_version': 1,
    'entitlement_id': 'e-1',
    'shop_id': 'shop-1',
    'device_id': device,
    'subscription_id': 's-1',
    'plan_id': 'pro_monthly',
    'issued_at': issued.toIso8601String(),
    'valid_until': issued.add(const Duration(days: 30)).toIso8601String(),
    'offline_grace_until': issued
        .add(const Duration(days: 37))
        .toIso8601String(),
    'server_time': issued.toIso8601String(),
  };
  SignedEntitlement sign(Map<String, dynamic> p) {
    final signer = Signer('SHA-256/RSA')
      ..init(
        true,
        PrivateKeyParameter<RSAPrivateKey>(keys.privateKey as RSAPrivateKey),
      );
    final sig =
        signer.generateSignature(
              Uint8List.fromList(utf8.encode(canonicalJson(p))),
            )
            as RSASignature;
    return SignedEntitlement(
      payload: p,
      signature: base64Url.encode(sig.bytes).replaceAll('=', ''),
      keyId: 'test',
      algorithm: 'RS256',
    );
  }

  Future<EntitlementEvaluation> evaluate({
    String device = 'tablet-1',
    Duration after = const Duration(days: 2),
  }) => policy.evaluate(
    shopId: 'shop-1',
    deviceId: device,
    localNow: issued.add(after),
  );

  group('offline entitlement', () {
    test('a valid signed entitlement allows offline billing', () async {
      store.token = sign(payload());
      store.time = TrustedTimeObservation(issued, issued);
      final value = await evaluate();
      expect(value.state, EntitlementState.active);
      expect(value.permitsMutation, isTrue);
    });

    test('a forged entitlement (edited expiry) is refused', () async {
      final forged = sign(payload());
      forged.payload['valid_until'] = issued
          .add(const Duration(days: 3650))
          .toIso8601String();
      store.token = forged;
      store.time = TrustedTimeObservation(issued, issued);
      final value = await evaluate();
      expect(value.state, EntitlementState.unavailable);
      expect(value.permitsMutation, isFalse);
    });

    test('a self-signed entitlement is refused', () async {
      final other =
          (RSAKeyGenerator()..init(
                ParametersWithRandom(
                  RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
                  FortunaRandom()..seed(
                    KeyParameter(Uint8List.fromList(List.filled(32, 9))),
                  ),
                ),
              ))
              .generateKeyPair();
      final p = payload();
      final signer = Signer('SHA-256/RSA')
        ..init(
          true,
          PrivateKeyParameter<RSAPrivateKey>(other.privateKey),
        );
      final sig =
          signer.generateSignature(
                Uint8List.fromList(utf8.encode(canonicalJson(p))),
              )
              as RSASignature;
      store.token = SignedEntitlement(
        payload: p,
        signature: base64Url.encode(sig.bytes),
        keyId: 'attacker',
        algorithm: 'RS256',
      );
      store.time = TrustedTimeObservation(issued, issued);
      expect((await evaluate()).permitsMutation, isFalse);
    });

    test('an entitlement copied to a third device is refused', () async {
      store.token = sign(payload(device: 'tablet-1'));
      store.time = TrustedTimeObservation(issued, issued);
      final value = await evaluate(device: 'copied-device-3');
      expect(value.state, EntitlementState.unavailable);
      expect(value.permitsMutation, isFalse);
    });

    test('expiry: grace warns, then billing stops', () async {
      store.token = sign(payload());
      store.time = TrustedTimeObservation(issued, issued);
      expect(
        (await evaluate(after: const Duration(days: 32))).state,
        EntitlementState.offlineGrace,
      );
      final expired = await evaluate(after: const Duration(days: 38));
      expect(expired.state, EntitlementState.expired);
      expect(expired.permitsMutation, isFalse);
    });
  });

  group('server refusal on reconnect', () {
    test('a suspended shop blocks billing despite a valid token', () async {
      store.token = sign(payload());
      store.time = TrustedTimeObservation(issued, issued);
      store.revocation = EntitlementRevocation('DPL01', issued);
      final value = await evaluate();
      expect(value.state, EntitlementState.revoked);
      expect(value.permitsMutation, isFalse);
      expect(value.message, contains('shop is not active'));
    });

    test('a revoked device blocks billing', () async {
      store.token = sign(payload());
      store.time = TrustedTimeObservation(issued, issued);
      store.revocation = EntitlementRevocation('DPL02', issued);
      final value = await evaluate();
      expect(value.permitsMutation, isFalse);
      expect(value.message, contains('device is not approved'));
    });

    test('only licensing refusals revoke; outages do not', () {
      expect(
        entitlementRefusalCode(
          const FunctionException(status: 403, details: {'code': 'DPL01'}),
        ),
        'DPL01',
      );
      expect(
        entitlementRefusalCode(
          const FunctionException(status: 403, details: {'code': 'DENIED'}),
        ),
        isNull,
      );
      expect(
        entitlementRefusalCode(
          const FunctionException(status: 503, details: {'code': 'DPL01'}),
        ),
        isNull,
      );
      expect(entitlementRefusalCode(TimeoutException('offline')), isNull);
    });

    Future<SupabaseEntitlementGateway> gateway(
      Future<http.Response> Function(http.Request) handler,
    ) async {
      final client = SupabaseClient(
        'http://127.0.0.1:1',
        'test-anon-key',
        httpClient: MockClient(handler),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      return SupabaseEntitlementGateway(
        client,
        EntitlementVerifier(keys.publicKey as RSAPublicKey),
        store,
      );
    }

    test('refusal is recorded, renewal clears it', () async {
      var refuse = true;
      final g = await gateway((request) async {
        expect(request.url.path, endsWith('/functions/v1/issue-entitlement'));
        if (refuse) {
          return http.Response(
            jsonEncode({'error': 'entitlement refused', 'code': 'DPL01'}),
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(sign(payload()).toJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await expectLater(
        g.refresh(shopId: 'shop-1', deviceId: 'tablet-1', localNow: issued),
        throwsA(isA<EntitlementRefused>()),
      );
      expect(store.revocation?.code, 'DPL01');
      expect((await evaluate()).permitsMutation, isFalse);

      refuse = false; // Admin reactivated and renewed.
      await g.refresh(shopId: 'shop-1', deviceId: 'tablet-1', localNow: issued);
      expect(store.revocation, isNull);
      expect((await evaluate()).permitsMutation, isTrue);
    });

    test('an outage keeps the cached entitlement usable', () async {
      store.token = sign(payload());
      store.time = TrustedTimeObservation(issued, issued);
      final g = await gateway((_) async => http.Response('down', 503));
      await expectLater(
        g.refresh(shopId: 'shop-1', deviceId: 'tablet-1', localNow: issued),
        throwsA(isNot(isA<EntitlementRefused>())),
      );
      expect(store.revocation, isNull);
      expect((await evaluate()).permitsMutation, isTrue);
    });
  });

  group('device classification', () {
    test('Android phones are mobile, Android tablets are tablets', () {
      expect(
        classifyDeviceType(
          isWeb: false,
          platform: TargetPlatform.android,
          shortestSide: 411,
        ),
        DeviceType.mobile,
      );
      expect(
        classifyDeviceType(
          isWeb: false,
          platform: TargetPlatform.android,
          shortestSide: 800,
        ),
        DeviceType.androidTablet,
      );
      expect(
        classifyDeviceType(
          isWeb: false,
          platform: TargetPlatform.windows,
          shortestSide: 900,
        ),
        DeviceType.windowsDesktop,
      );
    });

    test('approval status falls back for servers without licensing', () {
      const pending = RegisteredDevice(
        id: 'd',
        isActive: false,
        approvalStatus: 'pending',
      );
      expect(pending.awaitingApproval, isTrue);
      expect(const RegisteredDevice(id: 'd', isActive: true).rejected, isFalse);
    });
  });

  group('activation status', () {
    test('parses the owner_activation_status contract', () {
      final status = ActivationStatus.fromJson({
        'license_status': 'suspended',
        'plan_id': 'pro_monthly',
        'period_end': '2026-09-01T00:00:00+00:00',
        'server_time': '2026-10-14T00:00:00+00:00',
        'device_approval_status': 'pending',
      });
      expect(status.license, ShopLicense.suspended);
      expect(status.deviceApproval, DeviceApproval.pending);
      expect(status.subscriptionEnded, isTrue);
      expect(ActivationStatus.fromJson(const {}).license, ShopLicense.unknown);
    });

    for (final (locale, l10n) in [('en', _en), ('ur', _ur)]) {
      testWidgets('panel wording ($locale)', (tester) async {
        Future<void> show(ActivationStatus s) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: ActivationStatusPanel(status: s)),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show(
          ActivationStatus(
            license: ShopLicense.suspended,
            deviceApproval: DeviceApproval.approved,
            periodEnd: DateTime.utc(2026, 9, 1),
            serverTime: DateTime.utc(2026, 10, 14),
          ),
        );
        expect(find.text(l10n.activationShopSuspended), findsOneWidget);
        expect(find.textContaining('2026-09-01'), findsOneWidget);
        await show(
          ActivationStatus(
            license: ShopLicense.pending,
            deviceApproval: DeviceApproval.pending,
            periodEnd: DateTime.utc(2026, 12, 1),
            serverTime: DateTime.utc(2026, 10, 14),
          ),
        );
        expect(find.text(l10n.activationShopPending), findsOneWidget);
        expect(
          find.text(l10n.activationValidUntil('2026-12-01')),
          findsOneWidget,
        );
      });
    }

    test('every new licensing message is translated', () {
      for (final english in [
        'This shop is not active. Contact Dokan Pro Support.',
        'This device is not approved. Contact Dokan Pro Support.',
      ]) {
        expect(localizedMessage(_en, english), english);
        expect(localizedMessage(_ur, english), contains(_urduScript));
      }
      for (final pair in [
        (_en.activationContactSupport, _ur.activationContactSupport),
        (_en.deviceApprovalPending, _ur.deviceApprovalPending),
        (_en.deviceApprovalRejected, _ur.deviceApprovalRejected),
        (_en.activationNoShopBody, _ur.activationNoShopBody),
        (_en.authForgotPassword, _ur.authForgotPassword),
      ]) {
        expect(pair.$2, isNot(pair.$1));
        expect(pair.$2, contains(_urduScript));
      }
      expect(
        _en.activationContactSupport,
        'Contact Dokan Pro Support for Activation',
      );
    });
  });

  group('no public registration', () {
    Future<_Auth> pumpForm(WidgetTester tester, {String locale = 'en'}) async {
      final auth = _Auth();
      final lock = OwnerModeLock(_LockStore());
      await lock.load();
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AuthForm(
            auth: auth,
            session: AuthSessionController(auth),
            ownerLock: lock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('sign-in has no sign-up, only support contact', (tester) async {
      await pumpForm(tester);
      expect(find.text(_en.authCreateOwnerAccount), findsNothing);
      expect(find.text(_en.authSignUp), findsNothing);
      expect(find.text(_en.authFullName), findsNothing);
      expect(find.text(_en.activationContactSupport), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('sign-in is Urdu-ready', (tester) async {
      await pumpForm(tester, locale: 'ur');
      expect(find.text(_ur.activationContactSupport), findsOneWidget);
      expect(find.text(_ur.authForgotPassword), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('password recovery stays available', (tester) async {
      final auth = await pumpForm(tester);
      await tester.tap(find.text(_en.authForgotPassword));
      await tester.pumpAndSettle();
      expect(find.text(_en.authResetNeedsEmail), findsOneWidget);
      expect(auth.resets, isEmpty);
      await tester.enterText(find.byType(TextField).first, 'owner@shop.pk');
      await tester.tap(find.text(_en.authForgotPassword));
      await tester.pumpAndSettle();
      expect(auth.resets, ['owner@shop.pk']);
      expect(find.text(_en.authResetSent), findsOneWidget);
    });

    testWidgets('an account without a shop is sent to support', (tester) async {
      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NoShopPage(onSignOut: () async => signedOut = true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_en.activationNoShopBody), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text(_en.commonSignOut));
      expect(signedOut, isTrue);
    });
  });
}

final class _Store implements EntitlementStore {
  SignedEntitlement? token;
  TrustedTimeObservation? time;
  EntitlementRevocation? revocation;
  @override
  Future<SignedEntitlement?> read(String s, String d) async => token;
  @override
  Future<TrustedTimeObservation?> readTime(String s, String d) async => time;
  @override
  Future<void> write(
    String s,
    String d,
    SignedEntitlement t,
    TrustedTimeObservation v,
  ) async {
    token = t;
    time = v;
  }

  @override
  Future<EntitlementRevocation?> readRevocation(String s, String d) async =>
      revocation;
  @override
  Future<void> writeRevocation(
    String s,
    String d,
    EntitlementRevocation? value,
  ) async => revocation = value;
}

final class _Auth implements AuthRepository {
  final resets = <String>[];
  @override
  AppAuthState get current => const AppAuthState.signedOut();
  @override
  Stream<AppAuthState> get changes => const Stream.empty();
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset({required String email}) async =>
      resets.add(email);
}

final class _LockStore implements OwnerModeLockStore {
  bool value = false;
  @override
  Future<bool> read() async => value;
  @override
  Future<void> write(bool locked) async => value = locked;
}
