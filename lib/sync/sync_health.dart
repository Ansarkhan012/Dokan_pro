import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/domain/enums.dart';
import '../database/app_database.dart';

/// What the sync status chip shows. [needsAttention] wins over everything,
/// so the app never claims `Synced` while an operation needs the owner.
enum SyncHealth { synced, pending, syncing, needsAttention }

SyncHealth syncHealthOf(Iterable<SyncOperation> operations) {
  var health = SyncHealth.synced;
  for (final operation in operations) {
    switch (operation.status) {
      case SyncStatus.needsAttention || SyncStatus.blockedAuth:
        return SyncHealth.needsAttention;
      case SyncStatus.synced:
        if (operation.errorClass == 'flagged' &&
            operation.acknowledgedAt == null) {
          return SyncHealth.needsAttention;
        }
      case SyncStatus.syncing:
        health = SyncHealth.syncing;
      case SyncStatus.pending || SyncStatus.failed:
        if (health == SyncHealth.synced) health = SyncHealth.pending;
    }
  }
  return health;
}

/// Operations that decide [SyncHealth] for [shopId]: everything not synced,
/// plus synced operations with an unacknowledged server flag.
Stream<SyncHealth> watchShopSyncHealth(AppDatabase db, String shopId) =>
    (db.select(db.syncOperations)..where(
          (row) =>
              row.shopId.equals(shopId) &
              (row.status.equals(SyncStatus.synced.name).not() |
                  (row.errorClass.equals('flagged') &
                      row.acknowledgedAt.isNull())),
        ))
        .watch()
        .map(syncHealthOf)
        .distinct();

/// A worker identity unique to one runner instance (R1.6), so two runners on
/// one device (POS and an owner screen) never share or steal a live lease.
String uniqueSyncWorkerId(String prefix) => '$prefix-${const Uuid().v4()}';
