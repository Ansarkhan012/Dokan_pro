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
    appBar: AppBar(title: const Text('Sync issues')),
    body: FutureBuilder<AppDatabase>(
      future: db,
      builder: (context, snapshot) {
        final database = snapshot.data;
        if (database == null) {
          return snapshot.hasError
              ? const Center(child: Text('Could not open local data.'))
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
        return const Center(child: Text('No sync issues.'));
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Nothing here was deleted. Records stay on this device until '
            'they sync.',
          ),
          const SizedBox(height: 8),
          for (final operation in items) _tile(context, operation),
        ],
      );
    },
  );

  Widget _tile(BuildContext context, SyncOperation operation) {
    final flagged = operation.status == SyncStatus.synced;
    final at = (operation.attentionAt ?? operation.updatedAt).toLocal();
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: Icon(
          flagged ? Icons.flag_outlined : Icons.sync_problem,
          color: flagged ? Colors.orange : Theme.of(context).colorScheme.error,
        ),
        title: Text(_title(operation)),
        subtitle: Text(
          [
            operation.attentionReason ?? 'This record could not sync.',
            'Code: ${operation.errorCode ?? 'unknown_error'} • '
                '${flagged ? 'Synced, flagged' : _state(operation.status)} • '
                '${_time(at)} • attempts ${operation.retryCount}',
          ].join('\n'),
        ),
        trailing: flagged
            ? TextButton(
                onPressed: () =>
                    queue.acknowledgeFlag(operation.id, DateTime.now().toUtc()),
                child: const Text('Acknowledge'),
              )
            : TextButton(
                onPressed: () async {
                  await queue.retryAttention(
                    operation.id,
                    DateTime.now().toUtc(),
                  );
                  onRetried?.call();
                },
                child: const Text('Retry'),
              ),
      ),
    );
  }

  static String _title(SyncOperation operation) =>
      switch (operation.entityType) {
        'sale_aggregate' ||
        'sale' => 'Sale • ${billReference(operation.entityId)}',
        'sale_void' => 'Bill void',
        'sale_return' => 'Bill return',
        'customer_payment' => 'Customer payment',
        'purchase_aggregate' || 'purchase' => 'Purchase',
        'supplier_payment' => 'Supplier payment',
        'expense' => 'Expense',
        'inventory_movement' => 'Stock adjustment',
        final other => other,
      };

  static String _state(SyncStatus status) => switch (status) {
    SyncStatus.blockedAuth => 'Waiting for authorisation',
    _ => 'Needs attention',
  };

  static String _time(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}
