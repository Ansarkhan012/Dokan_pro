import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../database/repositories/sync_queue_repository.dart';
import '../sync/supabase_sale_upload_gateway.dart';
import '../sync/sync_health.dart';
import '../sync/sync_worker_runner.dart';

/// Work the owner queued earlier that could not sync while the device was in
/// cashier mode (owner-only operations are refused for the device credential)
/// is retried with the owner's session. Best effort: never throws.
Future<void> resumeOwnerSync({
  required SupabaseClient ownerClient,
  required String shopId,
  required String deviceId,
}) async {
  AppDatabase? db;
  try {
    db = await AppDatabase.open();
    final queue = SyncQueueRepository(db, shopId: shopId);
    await queue.resumeBlockedAuth(DateTime.now().toUtc());
    await SyncWorkerRunner(
      queue: queue,
      gateway: SupabaseSaleUploadGateway(ownerClient),
      workerId: uniqueSyncWorkerId('owner-$deviceId'),
    ).run();
  } catch (_) {
    // Pending work stays queued for the next owner or cashier sync.
  } finally {
    await db?.close();
  }
}
