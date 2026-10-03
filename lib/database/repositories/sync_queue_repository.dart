import 'dart:math';
import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../sync/sync_failure.dart';
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
                  (t) => t.id.equals(dependency) & t.shopId.equals(shopId),
                ))
                .getSingleOrNull();
        if (parent?.status == SyncStatus.needsAttention) {
          // The parent can never sync by itself, so neither can this one.
          await _needsAttention(
            candidate.id,
            now: now,
            errorClass: SyncFailureKind.permanent.name,
            code: 'parent_needs_attention',
            reason: 'An earlier record it depends on needs attention.',
            whereOwner: null,
          );
          continue;
        }
        if (parent?.status != SyncStatus.synced) continue;
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

  /// Marks the leased operation synced. [flags] are the server's
  /// record-and-flag rule codes (`accepted_flagged`): the operation is synced
  /// and the flag stays visible to the owner until acknowledged. Returns
  /// false, without writing, when [workerId] no longer owns the lease (the
  /// new owner re-uploads; the server answers `already_synced`).
  Future<bool> completeLease({
    required String id,
    required String workerId,
    required DateTime now,
    List<String> flags = const [],
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
                errorClass: Value(flags.isEmpty ? null : 'flagged'),
                errorCode: Value(flags.isEmpty ? null : flags.join(',')),
                attentionReason: Value(
                  flags.isEmpty
                      ? null
                      : 'Saved in the cloud, but it broke a shop rule '
                            '(${flags.map(_flagLabel).join(', ')}). Please '
                            'review it.',
                ),
                attentionAt: Value(flags.isEmpty ? null : now),
                firstErrorAt: const Value(null),
                unknownErrorCount: const Value(0),
              ),
            );
    return changed == 1;
  }

  /// Records a failed attempt (design §H). Connectivity and transient
  /// failures wait for their backoff and are retried without limit; unknown
  /// failures become `needsAttention` after [maxUnknownErrors] attempts or
  /// [unknownErrorWindow]; permanent ones immediately; auth ones become
  /// `blockedAuth`. [failure] null keeps the pre-R1.5 retryable behaviour.
  /// Returns false, without writing, when the lease was lost.
  Future<bool> failLease({
    required String id,
    required String workerId,
    required String error,
    required DateTime now,
    SyncFailure? failure,
  }) async {
    final current = await _owned(id);
    if (current.leaseOwner != workerId) return false;
    final kind = failure?.kind ?? SyncFailureKind.transient;
    switch (kind) {
      case SyncFailureKind.permanent:
        return _needsAttention(
          id,
          now: now,
          errorClass: kind.name,
          code: failure!.code,
          reason: failure.reason,
          lastError: error,
          whereOwner: workerId,
        );
      case SyncFailureKind.auth:
        return _write(
          id,
          workerId,
          SyncOperationsCompanion(
            status: const Value(SyncStatus.blockedAuth),
            retryCount: Value(current.retryCount + 1),
            lastError: Value(error),
            errorClass: Value(kind.name),
            errorCode: Value(failure!.code),
            attentionReason: Value(failure.reason),
            attentionAt: Value(now),
            nextAttemptAt: const Value(null),
            updatedAt: Value(now),
            leaseOwner: const Value(null),
            leaseExpiresAt: const Value(null),
          ),
        );
      case SyncFailureKind.unknown:
        final count = current.unknownErrorCount + 1;
        final first = current.firstErrorAt ?? now;
        if (count >= maxUnknownErrors ||
            now.difference(first) >= unknownErrorWindow) {
          return _needsAttention(
            id,
            now: now,
            errorClass: kind.name,
            code: failure!.code,
            reason: failure.reason,
            lastError: error,
            whereOwner: workerId,
            unknownErrorCount: count,
            firstErrorAt: first,
          );
        }
        return _retryLater(
          current,
          workerId,
          error,
          now,
          failure,
          unknownErrorCount: count,
          firstErrorAt: first,
        );
      case SyncFailureKind.connectivity || SyncFailureKind.transient:
        return _retryLater(current, workerId, error, now, failure);
    }
  }

  static const maxUnknownErrors = 5;
  static const unknownErrorWindow = Duration(hours: 1);

  /// Operations the owner must look at: not retried automatically, or synced
  /// with an unacknowledged server flag. Oldest first.
  Stream<List<SyncOperation>> watchAttention() => _attention().watch();
  Future<List<SyncOperation>> attention() => _attention().get();

  SimpleSelectStatement<$SyncOperationsTable, SyncOperation> _attention() =>
      db.select(db.syncOperations)
        ..where(
          (t) =>
              t.shopId.equals(shopId) &
              (t.status.isIn([
                    SyncStatus.needsAttention.name,
                    SyncStatus.blockedAuth.name,
                  ]) |
                  (t.status.equals(SyncStatus.synced.name) &
                      t.errorClass.equals('flagged') &
                      t.acknowledgedAt.isNull())),
        )
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

  /// Owner "Retry": the unchanged payload is queued again (the server is
  /// idempotent per operation). Counters reset; nothing is deleted. Its
  /// dependants that were only waiting on it are queued again as well.
  Future<void> retryAttention(String id, DateTime now) async {
    await _owned(id);
    await db.transaction(() async {
      await (db.update(db.syncOperations)..where(
            (t) =>
                t.id.equals(id) &
                t.shopId.equals(shopId) &
                t.status.isIn([
                  SyncStatus.needsAttention.name,
                  SyncStatus.blockedAuth.name,
                ]),
          ))
          .write(_requeued(now));
      await (db.update(db.syncOperations)..where(
            (t) =>
                t.shopId.equals(shopId) &
                t.dependsOnOperationId.equals(id) &
                t.status.equals(SyncStatus.needsAttention.name) &
                t.errorCode.equals('parent_needs_attention'),
          ))
          .write(_requeued(now));
    });
  }

  /// A new authorised session (auth-state change) unblocks `blockedAuth`.
  Future<int> resumeBlockedAuth(DateTime now) =>
      (db.update(db.syncOperations)..where(
            (t) =>
                t.shopId.equals(shopId) &
                t.status.equals(SyncStatus.blockedAuth.name),
          ))
          .write(_requeued(now));

  /// Owner has seen a server flag on a synced operation.
  Future<void> acknowledgeFlag(String id, DateTime now) async {
    await _owned(id);
    await (db.update(db.syncOperations)..where(
          (t) =>
              t.id.equals(id) &
              t.shopId.equals(shopId) &
              t.status.equals(SyncStatus.synced.name) &
              t.errorClass.equals('flagged'),
        ))
        .write(
          SyncOperationsCompanion(
            acknowledgedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  SyncOperationsCompanion _requeued(DateTime now) => SyncOperationsCompanion(
    status: const Value(SyncStatus.pending),
    retryCount: const Value(0),
    unknownErrorCount: const Value(0),
    firstErrorAt: const Value(null),
    nextAttemptAt: const Value(null),
    errorClass: const Value(null),
    errorCode: const Value(null),
    attentionReason: const Value(null),
    attentionAt: const Value(null),
    updatedAt: Value(now),
  );

  Future<bool> _retryLater(
    SyncOperation current,
    String workerId,
    String error,
    DateTime now,
    SyncFailure? failure, {
    int? unknownErrorCount,
    DateTime? firstErrorAt,
  }) {
    final retry = current.retryCount + 1;
    final delaySeconds = min(300, 1 << min(retry, 8));
    return _write(
      current.id,
      workerId,
      SyncOperationsCompanion(
        status: const Value(SyncStatus.failed),
        retryCount: Value(retry),
        lastError: Value(error),
        errorClass: Value(failure?.kind.name),
        errorCode: Value(failure?.code),
        attentionReason: Value(failure?.reason),
        unknownErrorCount: unknownErrorCount == null
            ? const Value.absent()
            : Value(unknownErrorCount),
        firstErrorAt: firstErrorAt == null
            ? const Value.absent()
            : Value(firstErrorAt),
        nextAttemptAt: Value(now.add(Duration(seconds: delaySeconds))),
        updatedAt: Value(now),
        leaseOwner: const Value(null),
        leaseExpiresAt: const Value(null),
      ),
    );
  }

  Future<bool> _needsAttention(
    String id, {
    required DateTime now,
    required String errorClass,
    required String? code,
    required String reason,
    required String? whereOwner,
    String? lastError,
    int? unknownErrorCount,
    DateTime? firstErrorAt,
  }) async {
    final changed =
        await (db.update(db.syncOperations)..where(
              (t) =>
                  t.id.equals(id) &
                  t.shopId.equals(shopId) &
                  (whereOwner == null
                      ? const Constant(true)
                      : t.leaseOwner.equals(whereOwner)),
            ))
            .write(
              SyncOperationsCompanion(
                status: const Value(SyncStatus.needsAttention),
                lastError: lastError == null
                    ? const Value.absent()
                    : Value(lastError),
                errorClass: Value(errorClass),
                errorCode: Value(code),
                attentionReason: Value(reason),
                attentionAt: Value(now),
                unknownErrorCount: unknownErrorCount == null
                    ? const Value.absent()
                    : Value(unknownErrorCount),
                firstErrorAt: firstErrorAt == null
                    ? const Value.absent()
                    : Value(firstErrorAt),
                nextAttemptAt: const Value(null),
                updatedAt: Value(now),
                leaseOwner: const Value(null),
                leaseExpiresAt: const Value(null),
              ),
            );
    return changed == 1;
  }

  Future<bool> _write(
    String id,
    String workerId,
    SyncOperationsCompanion values,
  ) async =>
      await (db.update(db.syncOperations)..where(
            (t) =>
                t.id.equals(id) &
                t.shopId.equals(shopId) &
                t.leaseOwner.equals(workerId),
          ))
          .write(values) ==
      1;

  static String _flagLabel(String code) => switch (code) {
    'credit_limit_exceeded' => 'customer credit limit exceeded',
    _ => code,
  };

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
