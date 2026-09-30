import 'dart:convert';
import 'dart:typed_data';
import 'package:dukaan_pro/subscription/entitlement.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:dukaan_pro/subscription/entitlement_store.dart';
import 'package:dukaan_pro/subscription/entitlement_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

void main() {
  late AsymmetricKeyPair<PublicKey, PrivateKey> keys;
  late _Store store;
  late EntitlementPolicyService policy;
  final base = DateTime.utc(2026, 1, 1);
  setUp(() {
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 1))));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
          random,
        ),
      );
    keys = generator.generateKeyPair();
    store = _Store();
    policy = EntitlementPolicyService(
      verifier: EntitlementVerifier(keys.publicKey as RSAPublicKey),
      store: store,
    );
  });
  SignedEntitlement token({
    String shop = 'shop',
    String device = 'device',
    String plan = 'trial',
    Duration valid = const Duration(days: 14),
    Duration grace = const Duration(days: 21),
  }) {
    final payload = <String, dynamic>{
      'entitlement_version': 1,
      'entitlement_id': 'e',
      'shop_id': shop,
      'device_id': device,
      'subscription_id': 's',
      'plan_id': plan,
      'issued_at': base.toIso8601String(),
      'valid_until': base.add(valid).toIso8601String(),
      'offline_grace_until': base.add(grace).toIso8601String(),
      'server_time': base.toIso8601String(),
    };
    final signer = Signer('SHA-256/RSA')
      ..init(
        true,
        PrivateKeyParameter<RSAPrivateKey>(keys.privateKey as RSAPrivateKey),
      );
    final sig =
        signer.generateSignature(
              Uint8List.fromList(utf8.encode(canonicalJson(payload))),
            )
            as RSASignature;
    return SignedEntitlement(
      payload: payload,
      signature: base64UrlEncode(sig.bytes).replaceAll('=', ''),
      keyId: 'test',
      algorithm: 'RS256',
    );
  }

  Future<void> cache(SignedEntitlement t) async =>
      store.write('shop', 'device', t, TrustedTimeObservation(base, base));
  test(
    'valid trial, progression, small correction, expiry and grace expiry',
    () async {
      await cache(token());
      expect(
        (await policy.evaluate(
          shopId: 'shop',
          deviceId: 'device',
          localNow: base,
        )).state,
        EntitlementState.trialActive,
      );
      expect(
        (await policy.evaluate(
          shopId: 'shop',
          deviceId: 'device',
          localNow: base.subtract(const Duration(minutes: 4)),
        )).permitsMutation,
        isTrue,
      );
      expect(
        (await policy.evaluate(
          shopId: 'shop',
          deviceId: 'device',
          localNow: base.add(const Duration(days: 15)),
        )).state,
        EntitlementState.offlineGrace,
      );
      expect(
        (await policy.evaluate(
          shopId: 'shop',
          deviceId: 'device',
          localNow: base.add(const Duration(days: 22)),
        )).decision,
        MutationDecision.block,
      );
    },
  );
  test('significant rollback blocks', () async {
    await cache(token());
    expect(
      (await policy.evaluate(
        shopId: 'shop',
        deviceId: 'device',
        localNow: base.subtract(const Duration(minutes: 6)),
      )).state,
      EntitlementState.clockVerificationRequired,
    );
  });
  test('tamper, wrong key, shop and device are rejected', () {
    final t = token();
    expect(
      () => policy.verifier.verify(
        SignedEntitlement(
          payload: {...t.payload, 'plan_id': 'pro_monthly'},
          signature: t.signature,
          keyId: t.keyId,
          algorithm: t.algorithm,
        ),
        shopId: 'shop',
        deviceId: 'device',
      ),
      throwsFormatException,
    );
    expect(
      () => policy.verifier.verify(t, shopId: 'other', deviceId: 'device'),
      throwsFormatException,
    );
    expect(
      () => policy.verifier.verify(t, shopId: 'shop', deviceId: 'other'),
      throwsFormatException,
    );
  });
  test('temporary outage keeps a valid cached monthly entitlement', () async {
    await cache(token(plan: 'starter_monthly'));
    expect(
      (await policy.evaluate(
        shopId: 'shop',
        deviceId: 'device',
        localNow: base.add(const Duration(days: 1)),
      )).state,
      EntitlementState.active,
    );
  });
}

final class _Store implements EntitlementStore {
  SignedEntitlement? token;
  TrustedTimeObservation? time;
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
}
