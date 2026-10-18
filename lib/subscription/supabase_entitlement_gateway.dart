import 'package:supabase_flutter/supabase_flutter.dart';
import 'entitlement.dart';
import 'entitlement_store.dart';
import 'entitlement_verifier.dart';

/// The server refused issuance for a licensing reason (see
/// [EntitlementRevocation]). Distinct from an outage, which keeps the cached
/// entitlement authoritative.
final class EntitlementRefused implements Exception {
  const EntitlementRefused(this.code);
  final String code;
  @override
  String toString() => 'EntitlementRefused($code)';
}

/// Licensing refusal codes that revoke local billing. Anything else (network,
/// 5xx, unknown 403s) is treated as a temporary outage.
const entitlementRevocationCodes = {'DPL01', 'DPL02', 'DPL03'};

/// The licensing code of a refused issue-entitlement call, or null.
String? entitlementRefusalCode(Object error) {
  if (error is! FunctionException || error.status != 403) return null;
  final details = error.details;
  final code = details is Map ? details['code'] : null;
  return code is String && entitlementRevocationCodes.contains(code)
      ? code
      : null;
}

final class SupabaseEntitlementGateway {
  const SupabaseEntitlementGateway(this.client, this.verifier, this.store);
  final SupabaseClient client;
  final EntitlementVerifier verifier;
  final EntitlementStore store;
  Future<EntitlementClaims> refresh({
    required String shopId,
    required String deviceId,
    required DateTime localNow,
  }) async {
    final FunctionResponse response;
    try {
      response = await client.functions.invoke(
        'issue-entitlement',
        body: {'shop_id': shopId, 'device_id': deviceId},
      );
    } catch (error) {
      final code = entitlementRefusalCode(error);
      if (code == null) rethrow;
      await store.writeRevocation(
        shopId,
        deviceId,
        EntitlementRevocation(code, localNow.toUtc()),
      );
      throw EntitlementRefused(code);
    }
    if (response.status < 200 ||
        response.status >= 300 ||
        response.data is! Map) {
      throw StateError('Entitlement issuance failed');
    }
    final token = SignedEntitlement.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    final claims = verifier.verify(token, shopId: shopId, deviceId: deviceId);
    await store.write(
      shopId,
      deviceId,
      token,
      TrustedTimeObservation(claims.serverTime, localNow.toUtc()),
    );
    // A renewed, reactivated or re-approved licence lifts the block.
    await store.writeRevocation(shopId, deviceId, null);
    return claims;
  }
}
