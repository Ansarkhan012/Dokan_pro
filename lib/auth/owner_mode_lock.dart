import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class OwnerModeLockStore {
  Future<bool> read();
  Future<void> write(bool locked);
}

final class SecureOwnerModeLockStore implements OwnerModeLockStore {
  SecureOwnerModeLockStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'dukaan_pro.owner_mode_locked.v1';
  final FlutterSecureStorage _storage;
  @override
  Future<bool> read() async => await _storage.read(key: _key) == 'true';
  @override
  Future<void> write(bool locked) => locked
      ? _storage.write(key: _key, value: 'true')
      : _storage.delete(key: _key);
}

/// Shared-tablet boundary between cashier mode and owner mode, on the device.
///
/// Entering cashier mode locks owner mode on this device (persisted, so an
/// app restart does not reopen it) and then removes the owner's Supabase
/// session (DeviceModeService); an owner session found while locked is
/// removed at startup. The server boundary is that removal: cashier mode has
/// only the device credential. Only a fresh owner sign-in, the owner's
/// password or a full sign-out releases the lock. Until the stored state has
/// loaded, owner access is denied.
final class OwnerModeLock extends ChangeNotifier {
  OwnerModeLock(this._store);
  final OwnerModeLockStore _store;
  bool? _locked;

  bool get isLoaded => _locked != null;
  bool get ownerAccessAllowed => _locked == false;

  Future<void> load() async {
    bool locked;
    try {
      locked = await _store.read();
    } catch (_) {
      locked = true; // An unreadable lock fails closed.
    }
    if (_locked != null) return; // engage/release already decided.
    _set(locked);
  }

  /// Locks owner mode before cashier mode is shown. Throws when the lock
  /// cannot be persisted, so the caller does not enter cashier mode.
  Future<void> engage() async {
    _set(true);
    await _store.write(true);
  }

  /// Call only after the owner proved identity (password or fresh sign-in).
  Future<void> release() async {
    _set(false);
    try {
      await _store.write(false);
    } catch (_) {
      // Owner identity was proven; a stale persisted lock only asks again.
    }
  }

  void _set(bool locked) {
    if (_locked == locked) return;
    _locked = locked;
    notifyListeners();
  }
}

abstract interface class OwnerReauthenticator {
  /// True when [password] belongs to the owner signed in on this device.
  /// Throws on network failure so it is not reported as a wrong password.
  Future<bool> verifyPassword(String password);
}

final class SupabaseOwnerReauthenticator implements OwnerReauthenticator {
  SupabaseOwnerReauthenticator(this.client);
  final SupabaseClient client;
  @override
  Future<bool> verifyPassword(String password) async {
    final owner = client.auth.currentUser;
    final email = owner?.email;
    if (owner == null || email == null || password.isEmpty) return false;
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user?.id == owner.id;
    } on AuthRetryableFetchException {
      rethrow;
    } on AuthException {
      return false;
    }
  }
}
