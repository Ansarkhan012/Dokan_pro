import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'entitlement.dart';

final class TrustedTimeObservation {
  const TrustedTimeObservation(this.serverUtc, this.localUtc);
  final DateTime serverUtc, localUtc;
  Map<String, dynamic> toJson() => {
    'server_utc': serverUtc.toIso8601String(),
    'local_utc': localUtc.toIso8601String(),
  };
  factory TrustedTimeObservation.fromJson(Map<String, dynamic> j) =>
      TrustedTimeObservation(
        DateTime.parse(j['server_utc'] as String).toUtc(),
        DateTime.parse(j['local_utc'] as String).toUtc(),
      );
}

abstract interface class EntitlementStore {
  Future<SignedEntitlement?> read(String shopId, String deviceId);
  Future<TrustedTimeObservation?> readTime(String shopId, String deviceId);
  Future<void> write(
    String shopId,
    String deviceId,
    SignedEntitlement token,
    TrustedTimeObservation time,
  );
}

final class SecureEntitlementStore implements EntitlementStore {
  SecureEntitlementStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String _key(String s, String d, String type) =>
      'dukaan_pro.entitlement.v1.$s.$d.$type';
  @override
  Future<SignedEntitlement?> read(String s, String d) async {
    final v = await _storage.read(key: _key(s, d, 'token'));
    return v == null
        ? null
        : SignedEntitlement.fromJson(jsonDecode(v) as Map<String, dynamic>);
  }

  @override
  Future<TrustedTimeObservation?> readTime(String s, String d) async {
    final v = await _storage.read(key: _key(s, d, 'time'));
    return v == null
        ? null
        : TrustedTimeObservation.fromJson(
            jsonDecode(v) as Map<String, dynamic>,
          );
  }

  @override
  Future<void> write(
    String s,
    String d,
    SignedEntitlement token,
    TrustedTimeObservation time,
  ) async {
    await _storage.write(
      key: _key(s, d, 'token'),
      value: jsonEncode(token.toJson()),
    );
    await _storage.write(
      key: _key(s, d, 'time'),
      value: jsonEncode(time.toJson()),
    );
  }
}
