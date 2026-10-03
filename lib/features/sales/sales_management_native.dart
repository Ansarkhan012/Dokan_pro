import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../subscription/subscription_runtime.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/sync_health.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_worker.dart';
import '../products/product_management_native.dart'
    show parseQuantity, quantityToInput;
import 'application/local_sale_return_service.dart';
import 'application/local_sale_void_service.dart';
import 'domain/sale_return.dart';
import 'sales_history.dart';

class SalesManagementScreen extends StatefulWidget {
  const SalesManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, shopName, deviceId;
  @override
  State<SalesManagementScreen> createState() => _State();
}

class _State extends State<SalesManagementScreen> {
  AppDatabase? db;
  late Future<AppDatabase> ready = _open();
  Future<AppDatabase> _open() async {
    final d = await AppDatabase.open();
    db = d;
    final uid = widget.client.auth.currentUser!.id,
        now = DateTime.now().toUtc();
    await d
        .into(d.shopUsers)
        .insertOnConflictUpdate(
          ShopUsersCompanion.insert(
            id: 'owner-${widget.shopId}-$uid',
            shopId: widget.shopId,
            userId: uid,
            role: ShopRole.owner,
            createdAt: now,
          ),
        );
    return d;
  }

  @override
  void dispose() {
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales & Returns')),
    body: FutureBuilder<AppDatabase>(
      future: ready,
      builder: (context, s) {
        if (s.hasError) {
          return const Center(child: Text('Sales could not be opened.'));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return SalesHistoryView(
          repository: DriftSalesHistoryRepository(
            s.data!,
            shopId: widget.shopId,
          ),
          shopName: widget.shopName,
          onReturn: _return,
          onVoid: _void,
        );
      },
    ),
  );
  Future<void> _sync() async {
    await SyncWorker(
      queue: SyncQueueRepository(db!, shopId: widget.shopId),
      gateway: SupabaseSaleUploadGateway(widget.client),
      workerId: uniqueSyncWorkerId('owner-${widget.deviceId}'),
    ).runOnce();
  }

  Future<void> _return(SaleHistoryDetail detail) async {
    final input = await showDialog<_ReturnInput>(
      context: context,
      builder: (_) => _ReturnDialog(detail: detail),
    );
    if (input == null || db == null) return;
    try {
      final items =
          await (db!.select(db!.saleItems)..where(
                (t) =>
                    t.shopId.equals(widget.shopId) &
                    t.saleId.equals(detail.sale.id),
              ))
              .get();
      await LocalSaleReturnService(
        db!,
        const UuidV7Generator(),
        authorizer: productionFinancialMutationAuthorizer(),
      ).create(
        SaleReturnDraft(
          shopId: widget.shopId,
          originalSaleId: detail.sale.id,
          ownerId: widget.client.auth.currentUser!.id,
          deviceId: widget.deviceId,
          refundMethod: input.method,
          reason: input.reason,
          lines: [
            for (var i = 0; i < items.length; i++)
              if (input.quantities[i] > 0)
                SaleReturnLineDraft(
                  originalSaleItemId: items[i].id,
                  quantity: input.quantities[i],
                ),
          ],
        ),
      );
      await _sync();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Return saved locally.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Return could not be saved. Check quantities and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _void(SaleHistoryDetail detail) async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void sale'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'Reason *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Void Sale'),
          ),
        ],
      ),
    );
    c.dispose();
    if (reason == null || reason.isEmpty || db == null) return;
    try {
      await LocalSaleVoidService(
        db!,
        const UuidV7Generator(),
        authorizer: productionFinancialMutationAuthorizer(),
      ).voidSale(
        shopId: widget.shopId,
        saleId: detail.sale.id,
        ownerId: widget.client.auth.currentUser!.id,
        deviceId: widget.deviceId,
        reason: reason,
      );
      await _sync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale void recorded locally.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Void is allowed only for an owner within 15 minutes and before any return.',
            ),
          ),
        );
      }
    }
  }
}

class _ReturnDialog extends StatefulWidget {
  const _ReturnDialog({required this.detail});
  final SaleHistoryDetail detail;
  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  late final quantities = [
    for (final _ in widget.detail.lines) TextEditingController(text: '0'),
  ];
  final reason = TextEditingController();
  PaymentMethod method = PaymentMethod.cash;
  @override
  void dispose() {
    for (final c in quantities) {
      c.dispose();
    }
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Return items'),
    content: SizedBox(
      width: 460,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (var i = 0; i < widget.detail.lines.length; i++)
            TextField(
              controller: quantities[i],
              decoration: InputDecoration(
                labelText:
                    '${widget.detail.lines[i].name} (sold ${quantityToInput(widget.detail.lines[i].quantity)})',
              ),
            ),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Refund method'),
            items: const [
              DropdownMenuItem(value: PaymentMethod.cash, child: Text('Cash')),
              DropdownMenuItem(
                value: PaymentMethod.digital,
                child: Text('Digital'),
              ),
              DropdownMenuItem(
                value: PaymentMethod.credit,
                child: Text('Udhaar adjustment'),
              ),
            ],
            onChanged: (v) => setState(() => method = v!),
          ),
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Reason *'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final q = quantities.map((c) => parseQuantity(c.text)).toList();
          if (q.any((x) => x == null) ||
              q.every((x) => x == 0) ||
              reason.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(
            context,
            _ReturnInput(q.cast<int>(), method, reason.text.trim()),
          );
        },
        child: const Text('Save Return'),
      ),
    ],
  );
}

final class _ReturnInput {
  const _ReturnInput(this.quantities, this.method, this.reason);
  final List<int> quantities;
  final PaymentMethod method;
  final String reason;
}
