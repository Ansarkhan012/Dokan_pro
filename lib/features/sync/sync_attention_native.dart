import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/cashier_session_store.dart';
import '../../core/domain/enums.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_health.dart';
import '../../sync/sync_worker_runner.dart';
import '../sales/domain/bill_reference.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/messages.dart';

/// Owner-only list of outbox operations that need attention (R1.5).
class SyncAttentionScreen extends StatefulWidget {
  const SyncAttentionScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  State<SyncAttentionScreen> createState() => _SyncAttentionScreenState();
}

class _SyncAttentionScreenState extends State<SyncAttentionScreen> {
  late final Future<AppDatabase> db = AppDatabase.open();

  @override
  void dispose() {
    db.then((value) => value.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.syncIssuesTitle)),
    body: FutureBuilder<AppDatabase>(
      future: db,
      builder: (context, snapshot) {
        final database = snapshot.data;
        if (database == null) {
          return snapshot.hasError
              ? Center(child: Text(context.l10n.commonLocalDataUnavailable))
              : const Center(child: CircularProgressIndicator());
        }
        final queue = SyncQueueRepository(database, shopId: widget.shopId);
        return SyncAttentionView(
          queue: queue,
          onRetried: SyncWorkerRunner(
            queue: queue,
            gateway: SupabaseSaleUploadGateway(widget.client),
            workerId: uniqueSyncWorkerId('owner-${widget.deviceId}'),
            cashierToken: () async =>
                (await SecureCashierSessionStore().read())?.token,
          ).wake,
        );
      },
    ),
  );
}

/// The list itself, separated from storage and network for tests.
class SyncAttentionView extends StatelessWidget {
  const SyncAttentionView({super.key, required this.queue, this.onRetried});
  final SyncQueueRepository queue;
  final VoidCallback? onRetried;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SyncOperation>>(
    stream: queue.watchAttention(),
    builder: (context, snapshot) {
      final items = snapshot.data;
      if (items == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (items.isEmpty) {
        return Center(child: Text(context.l10n.syncNoIssues));
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.l10n.syncNothingDeleted),
          const SizedBox(height: 8),
          for (final operation in items) _tile(context, operation),
        ],
      );
    },
  );

  Widget _tile(BuildContext context, SyncOperation operation) {
    final flagged = operation.status == SyncStatus.synced;
    final l10n = context.l10n;
    final at = (operation.attentionAt ?? operation.updatedAt).toLocal();
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: Icon(
          flagged ? Icons.flag_outlined : Icons.sync_problem,
          color: flagged ? Colors.orange : Theme.of(context).colorScheme.error,
        ),
        title: Text(_title(context, operation)),
        subtitle: Text(
          [
            // The stored reason stays in English for diagnostics; known
            // reasons are translated for display.
            switch (operation.attentionReason) {
              final reason? => localizedSyncReason(l10n, reason),
              null => l10n.syncReasonFallback,
            },
            l10n.syncAttentionDetails(
              bidiId(context, operation.errorCode ?? 'unknown_error'),
              flagged ? l10n.syncStateFlagged : _state(l10n, operation.status),
              bidiId(context, _time(at)),
              '${operation.retryCount}',
            ),
          ].join('\n'),
        ),
        trailing: flagged
            ? TextButton(
                onPressed: () =>
                    queue.acknowledgeFlag(operation.id, DateTime.now().toUtc()),
                child: Text(l10n.syncAcknowledge),
              )
            : TextButton(
                onPressed: () async {
                  await queue.retryAttention(
                    operation.id,
                    DateTime.now().toUtc(),
                  );
                  onRetried?.call();
                },
                child: Text(l10n.commonRetry),
              ),
      ),
    );
  }

  static String _title(BuildContext context, SyncOperation operation) {
    final l10n = context.l10n;
    return switch (operation.entityType) {
      'sale_aggregate' || 'sale' => l10n.syncEntitySale(
        bidiId(context, billReference(operation.entityId)),
      ),
      'sale_void' => l10n.syncEntityVoid,
      'sale_return' => l10n.syncEntityReturn,
      'customer_payment' => l10n.syncEntityCustomerPayment,
      'purchase_aggregate' || 'purchase' => l10n.syncEntityPurchase,
      'supplier_payment' => l10n.syncEntitySupplierPayment,
      'expense' => l10n.syncEntityExpense,
      'inventory_movement' => l10n.syncEntityStockAdjustment,
      final other => other,
    };
  }

  static String _state(AppLocalizations l10n, SyncStatus status) =>
      switch (status) {
        SyncStatus.blockedAuth => l10n.syncStateWaitingAuthorisation,
        _ => l10n.syncStatusNeedsAttention,
      };

  static String _time(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}
