import 'dart:convert';
import '../database/repositories/sync_queue_repository.dart';
import 'sale_upload_gateway.dart';
import 'sync_failure.dart';

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
  ///
  /// Never throws (O-6, R1.6): an upload failure is classified and recorded
  /// on its operation; a lost lease leaves the operation to its new owner
  /// (whose re-upload the server answers `already_synced`); a local queue
  /// failure ends this run with every operation still leased or queued, so
  /// a later run picks it up once the lease expires.
  Future<SyncWorkerResult> runOnce({int limit = 10}) async {
    var synced = 0;
    var failed = 0;
    var leaseLost = 0;
    try {
      for (var i = 0; i < limit; i++) {
        final operation = await queue.acquireLease(
          workerId: workerId,
          now: _clock().toUtc(),
        );
        if (operation == null) break;
        final Object? result;
        try {
          result = await gateway.uploadSaleAggregate(
            jsonDecode(operation.payload) as Map<String, dynamic>,
            cashierSessionToken: await cashierToken?.call(),
          );
        } catch (error) {
          failed++;
          final recorded = await queue.failLease(
            id: operation.id,
            workerId: workerId,
            error: error.toString(),
            now: _clock().toUtc(),
            failure: classifySyncError(error),
          );
          if (!recorded) leaseLost++;
          continue;
        }
        final owned = await queue.completeLease(
          id: operation.id,
          workerId: workerId,
          now: _clock().toUtc(),
          flags: serverFlagsOf(result),
        );
        if (owned) {
          synced++;
        } else {
          leaseLost++;
        }
      }
    } catch (_) {
      failed++; // The local queue failed (closed or busy database).
    }
    return SyncWorkerResult(
      synced: synced,
      failed: failed,
      leaseLost: leaseLost,
    );
  }
}

final class SyncWorkerResult {
  const SyncWorkerResult({
    required this.synced,
    required this.failed,
    this.leaseLost = 0,
  });
  final int synced;
  final int failed;

  /// Uploads whose lease another worker took meanwhile; the new owner
  /// completes them, so they are not counted as synced here.
  final int leaseLost;
}
