import 'dart:convert';

final class SignedEntitlement {
  const SignedEntitlement({
    required this.payload,
    required this.signature,
    required this.keyId,
    required this.algorithm,
  });
  final Map<String, dynamic> payload;
  final String signature, keyId, algorithm;
  Map<String, dynamic> toJson() => {
    'payload': payload,
    'signature': signature,
    'key_id': keyId,
    'algorithm': algorithm,
  };
  factory SignedEntitlement.fromJson(Map<String, dynamic> j) =>
      SignedEntitlement(
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        signature: j['signature'] as String,
        keyId: j['key_id'] as String,
        algorithm: j['algorithm'] as String,
      );
}

String canonicalJson(Object? value) {
  if (value is List) return '[${value.map(canonicalJson).join(',')}]';
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(value[k])}').join(',')}}';
  }
  return jsonEncode(value);
}

final class EntitlementClaims {
  const EntitlementClaims({
    required this.id,
    required this.shopId,
    required this.deviceId,
    required this.subscriptionId,
    required this.planId,
    required this.issuedAt,
    required this.validUntil,
    required this.offlineGraceUntil,
    required this.serverTime,
    required this.version,
  });
  final String id, shopId, deviceId, subscriptionId, planId;
  final DateTime issuedAt, validUntil, offlineGraceUntil, serverTime;
  final int version;
  factory EntitlementClaims.parse(Map<String, dynamic> p) {
    DateTime time(String key) {
      final raw = p[key];
      if (raw is! String) throw FormatException('$key is required');
      final value = DateTime.tryParse(raw);
      if (value == null || !raw.endsWith('Z') && !raw.contains('+')) {
        throw FormatException('$key must include timezone');
      }
      return value.toUtc();
    }

    final v = p['entitlement_version'];
    if (v != 1) throw UnsupportedError('Unsupported entitlement version');
    String text(String k) {
      final v = p[k];
      if (v is! String || v.isEmpty) throw FormatException('$k is required');
      return v;
    }

    final issued = time('issued_at'),
        valid = time('valid_until'),
        grace = time('offline_grace_until');
    if (valid.isBefore(issued) || grace.isBefore(valid)) {
      throw const FormatException('Invalid entitlement interval');
    }
    return EntitlementClaims(
      id: text('entitlement_id'),
      shopId: text('shop_id'),
      deviceId: text('device_id'),
      subscriptionId: text('subscription_id'),
      planId: text('plan_id'),
      issuedAt: issued,
      validUntil: valid,
      offlineGraceUntil: grace,
      serverTime: time('server_time'),
      version: v as int,
    );
  }
}
