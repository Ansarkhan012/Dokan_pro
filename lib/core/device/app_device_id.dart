import '../ids/id_generator.dart';

abstract interface class DeviceIdStore {
  Future<String?> read();
  Future<void> write(String value);
}

final class AppDeviceIdProvider {
  AppDeviceIdProvider(this.store, this.ids);
  final DeviceIdStore store;
  final IdGenerator ids;
  Future<String> getOrCreate() async {
    final existing = await store.read();
    if (existing != null && existing.isNotEmpty) return existing;
    final created = ids.next();
    await store.write(created);
    return created;
  }
}
