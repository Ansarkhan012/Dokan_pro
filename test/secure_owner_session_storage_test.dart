import 'package:dukaan_pro/auth/secure_owner_session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'sb-pilot-auth-token';
const _session = '{"access_token":"a","refresh_token":"r"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the key matches supabase_flutter\'s default storage key', () {
    expect(supabaseSessionKey('https://pilot.supabase.co'), _key);
  });

  test('upgrade moves a SharedPreferences session into secure storage', () async {
    SharedPreferences.setMockInitialValues({_key: _session});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = SecureOwnerSessionStorage(persistSessionKey: _key);

    await storage.initialize();

    expect(await storage.hasAccessToken(), isTrue, reason: 'owner stays signed in');
    expect(await storage.accessToken(), _session);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(_key), isFalse, reason: 'no plaintext copy');
  });

  test('a secure session is never overwritten by a stale plaintext one', () async {
    SharedPreferences.setMockInitialValues({_key: 'stale'});
    FlutterSecureStorage.setMockInitialValues({_key: _session});
    final storage = SecureOwnerSessionStorage(persistSessionKey: _key);

    await storage.initialize();

    expect(await storage.accessToken(), _session);
    expect((await SharedPreferences.getInstance()).containsKey(_key), isFalse);
  });

  test('persist and remove use secure storage only', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = SecureOwnerSessionStorage(persistSessionKey: _key);
    await storage.initialize();

    await storage.persistSession(_session);
    expect(await storage.hasAccessToken(), isTrue);
    expect((await SharedPreferences.getInstance()).containsKey(_key), isFalse);
    expect(await const FlutterSecureStorage().read(key: _key), _session);

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });
}
