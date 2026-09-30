import 'dart:io';

import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/subscription/entitlement.dart';
import 'package:dukaan_pro/subscription/entitlement_policy.dart';
import 'package:dukaan_pro/subscription/entitlement_store.dart';
import 'package:dukaan_pro/subscription/entitlement_verifier.dart';
import 'package:dukaan_pro/subscription/supabase_entitlement_gateway.dart';
import 'package:supabase/supabase.dart';
import 'package:flutter_test/flutter_test.dart';

const url = String.fromEnvironment('E2E_SUPABASE_URL');
const anonKey = String.fromEnvironment('E2E_SUPABASE_ANON_KEY');

void main() {
  test('development entitlement issuance E2E', _run);
}

Future<void> _run() async {
  if (url.isEmpty || anonKey.isEmpty) {
    throw StateError('Development E2E connection is not configured.');
  }
  final client = SupabaseClient(
    url,
    anonKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  final marker = DateTime.now().microsecondsSinceEpoch;
  final email = 'entitlement-e2e-$marker@example.test';
  const password = 'Development-only-123!';
  final auth = await client.auth.signUp(email: email, password: password);
  if (auth.session == null) throw StateError('Owner authentication failed.');

  final created = await client.rpc(
    'create_owner_shop',
    params: {'p_name': 'Entitlement E2E', 'p_phone': '', 'p_address': ''},
  );
  final shopId = ((created as List).single as Map)['shop_id'] as String;
  final registered = await client.rpc(
    'register_shop_device',
    params: {
      'p_shop_id': shopId,
      'p_device_name': 'E2E Counter',
      'p_device_type': DeviceType.windowsDesktop.name,
      'p_device_identifier': '10000000-0000-7000-8000-000000000001',
    },
  );
  final deviceId = ((registered as List).single as Map)['device_id'] as String;

  final store = _MemoryStore();
  final verifier = EntitlementVerifier(rsaPublicKeyFromEnvironment());
  final gateway = SupabaseEntitlementGateway(client, verifier, store);
  final claims = await gateway.refresh(
    shopId: shopId,
    deviceId: deviceId,
    localNow: DateTime.now(),
  );
  _require(claims.shopId == shopId, 'Issued shop binding differs.');
  _require(claims.deviceId == deviceId, 'Issued device binding differs.');
  _require(claims.planId == 'trial', 'Trial subscription was not issued.');

  final token = (await store.read(shopId, deviceId))!;
  final evaluation = await EntitlementPolicyService(
    verifier: verifier,
    store: store,
  ).evaluate(shopId: shopId, deviceId: deviceId, localNow: DateTime.now());
  _require(
    evaluation.state == EntitlementState.trialActive &&
        evaluation.permitsMutation,
    'Flutter policy did not accept the issued trial entitlement.',
  );

  _expectFailure(
    () => verifier.verify(token, shopId: shopId, deviceId: 'wrong'),
    'wrong device binding',
  );
  _expectFailure(
    () => verifier.verify(token, shopId: 'wrong', deviceId: deviceId),
    'wrong shop binding',
  );
  final tamperedPayload = Map<String, dynamic>.from(token.payload)
    ..['plan_id'] = 'annual';
  _expectFailure(
    () => verifier.verify(
      SignedEntitlement(
        payload: tamperedPayload,
        signature: token.signature,
        keyId: token.keyId,
        algorithm: token.algorithm,
      ),
      shopId: shopId,
      deviceId: deviceId,
    ),
    'tampered entitlement',
  );

  await _expectHttpFailure(
    client.functions.invoke(
      'issue-entitlement',
      body: {
        'shop_id': shopId,
        'device_id': '20000000-0000-7000-8000-000000000002',
      },
    ),
    'unknown device issuance',
  );
  await _expectHttpFailure(
    client.functions.invoke(
      'issue-entitlement',
      body: {
        'shop_id': '30000000-0000-7000-8000-000000000003',
        'device_id': deviceId,
      },
    ),
    'unauthorized shop issuance',
  );
  await _expectHttpFailure(
    client.functions.invoke('issue-entitlement', body: {'unexpected': true}),
    'malformed issuance',
  );
  final revoke = await Process.run('docker', [
    'exec',
    'supabase_db_POS_store',
    'psql',
    '-U',
    'postgres',
    '-d',
    'postgres',
    '-v',
    'ON_ERROR_STOP=1',
    '-c',
    "update public.devices set is_active=false where id='$deviceId'::uuid",
  ]);
  _require(revoke.exitCode == 0, 'Could not revoke the E2E device.');
  await _expectHttpFailure(
    client.functions.invoke(
      'issue-entitlement',
      body: {'shop_id': shopId, 'device_id': deviceId},
    ),
    'revoked device issuance',
  );
  await client.auth.signOut();
  client.dispose();
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectFailure(void Function() action, String label) {
  try {
    action();
  } catch (_) {
    return;
  }
  throw StateError('$label was accepted.');
}

Future<void> _expectHttpFailure(
  Future<FunctionResponse> request,
  String label,
) async {
  try {
    final response = await request;
    if (response.status >= 400) return;
  } catch (_) {
    return;
  }
  throw StateError('$label was accepted.');
}

final class _MemoryStore implements EntitlementStore {
  SignedEntitlement? token;
  TrustedTimeObservation? time;
  @override
  Future<SignedEntitlement?> read(String shopId, String deviceId) async =>
      token;
  @override
  Future<TrustedTimeObservation?> readTime(
    String shopId,
    String deviceId,
  ) async => time;
  @override
  Future<void> write(
    String shopId,
    String deviceId,
    SignedEntitlement value,
    TrustedTimeObservation observation,
  ) async {
    token = value;
    time = observation;
  }
}
