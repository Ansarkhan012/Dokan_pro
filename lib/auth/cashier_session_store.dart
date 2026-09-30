import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'cashier_session.dart';

abstract interface class CashierSessionStore {
  Future<CashierSession?> read();
  Future<void> write(CashierSession session);
  Future<void> clear();
}

final class SecureCashierSessionStore implements CashierSessionStore {
  SecureCashierSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'dukaan_pro.cashier_session.v1';
  final FlutterSecureStorage _storage;
  @override
  Future<CashierSession?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null
        ? null
        : CashierSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(CashierSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
