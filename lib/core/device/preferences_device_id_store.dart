import 'package:shared_preferences/shared_preferences.dart';
import 'app_device_id.dart';

final class PreferencesDeviceIdStore implements DeviceIdStore {
  static const _key = 'dukaan_pro.app_device_id.v1';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);
  @override
  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(_key, value);
  }
}
