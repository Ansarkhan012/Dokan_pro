import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The key supabase_flutter uses for its default SharedPreferences storage.
String supabaseSessionKey(String supabaseUrl) =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

/// Persists the owner's Supabase session (access and refresh token) in the
/// platform's secure storage instead of plain SharedPreferences.
///
/// Upgrade: a session saved by an earlier app version under the same key in
/// SharedPreferences is moved here once, then deleted there, so the owner
/// stays signed in and no plaintext copy remains.
final class SecureOwnerSessionStorage extends LocalStorage {
  SecureOwnerSessionStorage({
    required this.persistSessionKey,
    FlutterSecureStorage? secure,
    Future<SharedPreferences> Function()? preferences,
  }) : _secure = secure ?? const FlutterSecureStorage(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  final String persistSessionKey;
  final FlutterSecureStorage _secure;
  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<void> initialize() async {
    final preferences = await _preferences();
    final legacy = preferences.getString(persistSessionKey);
    if (legacy == null) return;
    if (!await _secure.containsKey(key: persistSessionKey)) {
      await _secure.write(key: persistSessionKey, value: legacy);
    }
    await preferences.remove(persistSessionKey);
  }

  @override
  Future<bool> hasAccessToken() => _secure.containsKey(key: persistSessionKey);

  @override
  Future<String?> accessToken() => _secure.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() async {
    await _secure.delete(key: persistSessionKey);
    // Belt and braces: never leave a pre-upgrade plaintext copy behind.
    await (await _preferences()).remove(persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secure.write(key: persistSessionKey, value: persistSessionString);
}
