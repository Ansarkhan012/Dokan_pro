abstract interface class SyncService {
  Future<SyncRunResult> pushPending({
    required String shopId,
    required String deviceId,
  });
  Future<SyncRunResult> pullChanges({
    required String shopId,
    required String deviceId,
  });
}

final class SyncRunResult {
  const SyncRunResult({required this.processed, required this.failed});
  final int processed;
  final int failed;
}

final class OfflineOnlySyncService implements SyncService {
  const OfflineOnlySyncService();
  @override
  Future<SyncRunResult> pullChanges({
    required String shopId,
    required String deviceId,
  }) async => const SyncRunResult(processed: 0, failed: 0);
  @override
  Future<SyncRunResult> pushPending({
    required String shopId,
    required String deviceId,
  }) async => const SyncRunResult(processed: 0, failed: 0);
}
