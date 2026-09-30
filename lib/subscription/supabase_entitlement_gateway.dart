import 'package:supabase_flutter/supabase_flutter.dart';
import 'entitlement.dart';
import 'entitlement_store.dart';
import 'entitlement_verifier.dart';

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
    final response = await client.functions.invoke(
      'issue-entitlement',
      body: {'shop_id': shopId, 'device_id': deviceId},
    );
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
    return claims;
  }
}
