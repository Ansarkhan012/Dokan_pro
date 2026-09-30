import 'package:drift/drift.dart';
import '../auth/cashier_session_store.dart';
import '../core/domain/enums.dart';
import '../database/app_database.dart';

final class DevelopmentDiagnostics {
  DevelopmentDiagnostics(this.db, this.sessions);
  final AppDatabase db;
  final CashierSessionStore sessions;
  Future<Map<String, Object?>> snapshot({
    required String shopId,
    required String deviceId,
    bool supabaseConfigured = false,
  }) async {
    Future<int> count(SyncStatus status) async {
      final expression = db.syncOperations.id.count();
      final query = db.selectOnly(db.syncOperations)
        ..addColumns([expression])
        ..where(
          db.syncOperations.shopId.equals(shopId) &
              db.syncOperations.status.equals(status.name),
        );
      return query.map((row) => row.read(expression) ?? 0).getSingle();
    }

    final cursors =
        await (db.select(db.syncCursors)
              ..where((t) => t.shopId.equals(shopId))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    final session = await sessions.read();
    final leases = await (db.select(
      db.syncOperations,
    )..where((t) => t.shopId.equals(shopId) & t.leaseOwner.isNotNull())).get();
    return {
      'supabase_configured': supabaseConfigured,
      'device_id': deviceId,
      'cashier_session_present': session != null,
      'cashier_session_expires_at': session?.expiresAt.toIso8601String(),
      'last_successful_pull': cursors.firstOrNull?.updatedAt.toIso8601String(),
      'pending': await count(SyncStatus.pending),
      'failed': await count(SyncStatus.failed),
      'syncing': await count(SyncStatus.syncing),
      'active_leases': leases.length,
    };
  }
}
