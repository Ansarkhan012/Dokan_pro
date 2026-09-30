import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'entitlement.dart';

final class EntitlementVerifier {
  const EntitlementVerifier(this.publicKey);
  final RSAPublicKey publicKey;
  EntitlementClaims verify(
    SignedEntitlement token, {
    required String shopId,
    required String deviceId,
  }) {
    if (token.algorithm != 'RS256') {
      throw const FormatException('Unsupported signature algorithm');
    }
    final signer = Signer('SHA-256/RSA')
      ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
    final signature = base64Url.decode(base64Url.normalize(token.signature));
    final ok = signer.verifySignature(
      Uint8List.fromList(utf8.encode(canonicalJson(token.payload))),
      RSASignature(signature),
    );
    if (!ok) throw const FormatException('Invalid entitlement signature');
    final claims = EntitlementClaims.parse(token.payload);
    if (claims.shopId != shopId) {
      throw const FormatException('Entitlement belongs to another shop');
    }
    if (claims.deviceId != deviceId) {
      throw const FormatException('Entitlement belongs to another device');
    }
    return claims;
  }
}

RSAPublicKey rsaPublicKeyFromEnvironment() {
  const n = String.fromEnvironment('ENTITLEMENT_RSA_MODULUS_B64URL');
  const e = String.fromEnvironment(
    'ENTITLEMENT_RSA_EXPONENT_B64URL',
    defaultValue: 'AQAB',
  );
  if (n.isEmpty) throw StateError('Entitlement public key is not configured');
  BigInt decode(String v) => BigInt.parse(
    base64Url
        .decode(base64Url.normalize(v))
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join(),
    radix: 16,
  );
  return RSAPublicKey(decode(n), decode(e));
}
