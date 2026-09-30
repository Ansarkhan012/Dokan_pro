import 'dart:math';
import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../app_database.dart';

final class SyncQueueRepository {
  SyncQueueRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  Future<List<SyncOperation>> pending() =>
      (db.select(db.syncOperations)
            ..where(
              (t) =>
                  t.shopId.equals(shopId) &
                  (t.status.equals(SyncStatus.pending.name) |
                      t.status.equals(SyncStatus.failed.name)),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<void> markSyncing(String id) => _transition(id, SyncStatus.syncing);
  Future<void> markPending(String id) =>
      _transition(id, SyncStatus.pending, lastError: const Value(null));
  Future<void> markSynced(String id, DateTime at) => _transition(
    id,
    SyncStatus.synced,
    syncedAt: Value(at),
    lastError: const Value(null),
  );
  Future<void> markFailed(String id, String error) async {
    final current = await _owned(id);
    await (db.update(
      db.syncOperations,
    )..where((t) => t.id.equals(id) & t.shopId.equals(shopId))).write(
      SyncOperationsCompanion(
        status: const Value(SyncStatus.failed),
        retryCount: Value(current.retryCount + 1),
        lastError: Value(error),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Atomically claims the oldest due operation. Expired syncing leases are
  /// eligible, so a process crash cannot strand work forever.
  Future<SyncOperation?> acquireLease({
    required String workerId,
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 2),
  }) => db.transaction(() async {
    final candidates =
        await (db.select(db.syncOperations)
              ..where(
                (t) =>
                    t.shopId.equals(shopId) &
                    (t.status.equals(SyncStatus.pending.name) |
                        t.status.equals(SyncStatus.failed.name) |
                        (t.status.equals(SyncStatus.syncing.name) &
                            t.leaseExpiresAt.isSmallerOrEqualValue(now))) &
                    (t.nextAttemptAt.isNull() |
                        t.nextAttemptAt.isSmallerOrEqualValue(now)),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    for (final candidate in candidates) {
      if (candidate.dependsOnOperationId case final dependency?) {
        final parent =
            await (db.select(db.syncOperations)..where(
                  (t) =>
                      t.id.equals(dependency) &
                      t.shopId.equals(shopId) &
                      t.status.equals(SyncStatus.synced.name),
                ))
                .getSingleOrNull();
        if (parent == null) continue;
      }
      final changed =
          await (db.update(db.syncOperations)..where(
                (t) =>
                    t.id.equals(candidate.id) &
                    t.shopId.equals(shopId) &
                    (t.leaseExpiresAt.isNull() |
                        t.leaseExpiresAt.isSmallerOrEqualValue(now) |
                        t.leaseOwner.equals(workerId)),
              ))
              .write(
                SyncOperationsCompanion(
                  status: const Value(SyncStatus.syncing),
                  leaseOwner: Value(workerId),
                  leaseExpiresAt: Value(now.add(leaseDuration)),
                  lastAttemptAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
      if (changed == 1) return _owned(candidate.id);
    }
    return null;
  });

  Future<void> completeLease({
    required String id,
    required String workerId,
    required DateTime now,
  }) async {
    final changed =
        await (db.update(db.syncOperations)..where(
              (t) =>
                  t.id.equals(id) &
                  t.shopId.equals(shopId) &
                  t.leaseOwner.equals(workerId),
            ))
            .write(
              SyncOperationsCompanion(
                status: const Value(SyncStatus.synced),
                syncedAt: Value(now),
                updatedAt: Value(now),
                leaseOwner: const Value(null),
                leaseExpiresAt: const Value(null),
                nextAttemptAt: const Value(null),
                lastError: const Value(null),
              ),
            );
    if (changed != 1) throw StateError('Worker does not own sync lease');
  }

  Future<void> failLease({
    required String id,
    required String workerId,
    required String error,
    required DateTime now,
  }) async {
    final current = await _owned(id);
    if (current.leaseOwner != workerId) {
      throw StateError('Worker does not own sync lease');
    }
    final retry = current.retryCount + 1;
    final delaySeconds = min(300, 1 << min(retry, 8));
    await (db.update(db.syncOperations)..where(
          (t) =>
              t.id.equals(id) &
              t.shopId.equals(shopId) &
              t.leaseOwner.equals(workerId),
        ))
        .write(
          SyncOperationsCompanion(
            status: const Value(SyncStatus.failed),
            retryCount: Value(retry),
            lastError: Value(error),
            nextAttemptAt: Value(now.add(Duration(seconds: delaySeconds))),
            updatedAt: Value(now),
            leaseOwner: const Value(null),
            leaseExpiresAt: const Value(null),
          ),
        );
  }

  Future<SyncOperation> _owned(String id) async {
    final row =
        await (db.select(db.syncOperations)
              ..where((t) => t.id.equals(id) & t.shopId.equals(shopId)))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Sync operation is outside repository shop');
    }
    return row;
  }

  Future<void> _transition(
    String id,
    SyncStatus status, {
    Value<DateTime?> syncedAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) async {
    await _owned(id);
    await (db.update(
      db.syncOperations,
    )..where((t) => t.id.equals(id) & t.shopId.equals(shopId))).write(
      SyncOperationsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now().toUtc()),
        syncedAt: syncedAt,
        lastError: lastError,
      ),
    );
  }
}
