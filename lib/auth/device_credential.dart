import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Request header the server's device-credential validator reads.
const deviceCredentialHeader = 'x-dukaan-device';

/// The registered device's credential for cashier mode: proves this device of
/// this shop to the server, and nothing about any person. Issued only to the
/// signed-in owner (`issue_device_credential`); the server keeps only its
/// hash. Lives only in secure storage: never in SQLite, the outbox or logs.
final class DeviceCredential {
  const DeviceCredential({
    required this.shopId,
    required this.shopName,
    required this.deviceId,
    required this.deviceIdentifier,
    required this.secret,
  });
  final String shopId;
  final String shopName;
  final String deviceId;
  final String deviceIdentifier;
  final String secret;

  String get headerValue => '$deviceId.$secret';

  bool belongsTo({required String shopId, required String deviceId}) =>
      this.shopId == shopId && this.deviceId == deviceId;

  Map<String, dynamic> toJson() => {
    'shop_id': shopId,
    'shop_name': shopName,
    'device_id': deviceId,
    'device_identifier': deviceIdentifier,
    'secret': secret,
  };

  factory DeviceCredential.fromJson(Map<String, dynamic> json) =>
      DeviceCredential(
        shopId: json['shop_id']! as String,
        shopName: json['shop_name']! as String,
        deviceId: json['device_id']! as String,
        deviceIdentifier: json['device_identifier']! as String,
        secret: json['secret']! as String,
      );

  @override
  String toString() => 'DeviceCredential(shop: $shopId, device: $deviceId)';
}

abstract interface class DeviceCredentialStore {
  Future<DeviceCredential?> read();
  Future<void> write(DeviceCredential credential);
  Future<void> clear();
}

final class SecureDeviceCredentialStore implements DeviceCredentialStore {
  SecureDeviceCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'dukaan_pro.device_credential.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<DeviceCredential?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null
        ? null
        : DeviceCredential.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(DeviceCredential credential) =>
      _storage.write(key: _key, value: jsonEncode(credential.toJson()));
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Owner-only provisioning; issuing again rotates the server's credential.
abstract interface class DeviceCredentialIssuer {
  Future<String> issue({required String shopId, required String deviceId});
}

final class SupabaseDeviceCredentialIssuer implements DeviceCredentialIssuer {
  SupabaseDeviceCredentialIssuer(this.ownerClient);
  final SupabaseClient ownerClient;
  @override
  Future<String> issue({
    required String shopId,
    required String deviceId,
  }) async {
    final secret = await ownerClient.rpc(
      'issue_device_credential',
      params: {'p_shop_id': shopId, 'p_device_id': deviceId},
    );
    if (secret is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(secret)) {
      throw StateError('The server returned no device credential.');
    }
    return secret;
  }
}

/// Session-less client for cashier mode: the anon key plus the device
/// credential header, no persisted or refreshable session of any user.
SupabaseClient deviceSupabaseClient({
  required String url,
  required String anonKey,
  required DeviceCredential credential,
}) => SupabaseClient(
  url,
  anonKey,
  headers: {deviceCredentialHeader: credential.headerValue},
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);
