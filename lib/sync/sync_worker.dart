import 'dart:convert';
import '../database/repositories/sync_queue_repository.dart';
import 'sale_upload_gateway.dart';

final class SyncWorker {
  SyncWorker({
    required this.queue,
    required this.gateway,
    required this.workerId,
    this.cashierToken,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final SyncQueueRepository queue;
  final SaleUploadGateway gateway;
  final String workerId;
  final Future<String?> Function()? cashierToken;
  final DateTime Function() _clock;

  /// Processes at most [limit] operations. Call from lifecycle opportunities;
  /// this class intentionally owns no timer or connectivity loop.
  Future<SyncWorkerResult> runOnce({int limit = 10}) async {
    var synced = 0;
    var failed = 0;
    for (var i = 0; i < limit; i++) {
      final now = _clock().toUtc();
      final operation = await queue.acquireLease(workerId: workerId, now: now);
      if (operation == null) break;
      try {
        await gateway.uploadSaleAggregate(
          jsonDecode(operation.payload) as Map<String, dynamic>,
          cashierSessionToken: await cashierToken?.call(),
        );
        await queue.completeLease(
          id: operation.id,
          workerId: workerId,
          now: _clock().toUtc(),
        );
        synced++;
      } catch (error) {
        await queue.failLease(
          id: operation.id,
          workerId: workerId,
          error: error.toString(),
          now: _clock().toUtc(),
        );
        failed++;
      }
    }
    return SyncWorkerResult(synced: synced, failed: failed);
  }
}

final class SyncWorkerResult {
  const SyncWorkerResult({required this.synced, required this.failed});
  final int synced;
  final int failed;
}
