import 'dart:convert';
import '../database/repositories/sync_queue_repository.dart';
import 'sale_upload_gateway.dart';

final class SaleSyncCoordinator {
  SaleSyncCoordinator(this.queue, this.gateway, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final SyncQueueRepository queue;
  final SaleUploadGateway gateway;
  final DateTime Function() _clock;
  Future<bool> upload(String operationId) async {
    final operation = (await queue.pending())
        .where((o) => o.id == operationId)
        .single;
    if (operation.status.name == 'failed') await queue.markPending(operationId);
    await queue.markSyncing(operationId);
    try {
      await gateway.uploadSaleAggregate(
        jsonDecode(operation.payload) as Map<String, dynamic>,
      );
      await queue.markSynced(operationId, _clock().toUtc());
      return true;
    } catch (error) {
      await queue.markFailed(operationId, error.toString());
      return false;
    }
  }
}
