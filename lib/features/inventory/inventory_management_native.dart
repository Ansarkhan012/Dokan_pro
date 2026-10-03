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
import 'drift_inventory_repository.dart';
import 'inventory_models.dart';
import 'local_inventory_adjustment_service.dart';

class InventoryManagementScreen extends StatefulWidget {
  const InventoryManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  State<InventoryManagementScreen> createState() =>
      _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen> {
  AppDatabase? db;
  final search = TextEditingController();
  InventoryFilter filter = InventoryFilter.all;
  late Future<(List<InventoryProductRow>, List<InventoryMovementRow>)> data =
      _open();

  Future<(List<InventoryProductRow>, List<InventoryMovementRow>)>
  _open() async {
    db ??= await AppDatabase.open();
    final repository = DriftInventoryRepository(db!, shopId: widget.shopId);
    return (
      await repository.products(search: search.text, filter: filter),
      await repository.history(),
    );
  }

  void refresh() => setState(() => data = _open());
  @override
  void dispose() {
    search.dispose();
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventory')),
    body: FutureBuilder<(List<InventoryProductRow>, List<InventoryMovementRow>)>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Inventory could not be loaded.'),
                FilledButton(
                  onPressed: refresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snapshot.data!.$1, history = snapshot.data!.$2;
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Current Stock'),
                  Tab(text: 'Movement History'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: 320,
                                child: TextField(
                                  controller: search,
                                  onSubmitted: (_) => refresh(),
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search),
                                    labelText: 'Search product or barcode',
                                  ),
                                ),
                              ),
                              SegmentedButton<InventoryFilter>(
                                segments: const [
                                  ButtonSegment(
                                    value: InventoryFilter.all,
                                    label: Text('All'),
                                  ),
                                  ButtonSegment(
                                    value: InventoryFilter.lowStock,
                                    label: Text('Low'),
                                  ),
                                  ButtonSegment(
                                    value: InventoryFilter.outOfStock,
                                    label: Text('Out'),
                                  ),
                                ],
                                selected: {filter},
                                onSelectionChanged: (v) {
                                  filter = v.single;
                                  refresh();
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: products.isEmpty
                              ? const Center(
                                  child: Text('No products match this filter.'),
                                )
                              : ListView.builder(
                                  itemCount: products.length,
                                  itemBuilder: (_, i) {
                                    final p = products[i];
                                    return ListTile(
                                      leading: Icon(
                                        p.isOutOfStock
                                            ? Icons
                                                  .remove_shopping_cart_outlined
                                            : p.isLowStock
                                            ? Icons.warning_amber
                                            : Icons.inventory_2_outlined,
                                      ),
                                      title: Text(p.name),
                                      subtitle: Text(
                                        '${p.unit} • ${p.barcode ?? 'No barcode'}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            quantityToInput(p.stockQuantity),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          OutlinedButton(
                                            onPressed: () => _adjust(p),
                                            child: const Text('Adjust'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                    history.isEmpty
                        ? const Center(child: Text('No stock movements yet.'))
                        : ListView.builder(
                            itemCount: history.length,
                            itemBuilder: (_, i) {
                              final m = history[i];
                              return ListTile(
                                title: Text(m.productName),
                                subtitle: Text(
                                  '${m.type.name} • ${m.note ?? 'No note'}\n${m.createdAt.toLocal()}',
                                ),
                                isThreeLine: true,
                                trailing: Text(
                                  '${m.quantity > 0 ? '+' : ''}${quantityToInput(m.quantity)}',
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _adjust(InventoryProductRow product) async {
    final input = await showDialog<(InventoryMovementType, int, String)>(
      context: context,
      builder: (_) => _AdjustmentDialog(product: product),
    );
    if (input == null || db == null) return;
    try {
      await LocalInventoryAdjustmentService(
        db!,
        const UuidV7Generator(),
        authorizer: productionFinancialMutationAuthorizer(),
      ).record(
        shopId: widget.shopId,
        productId: product.id,
        ownerId: widget.client.auth.currentUser!.id,
        deviceId: widget.deviceId,
        type: input.$1,
        quantity: input.$2,
        note: input.$3,
      );
      await SyncWorker(
        queue: SyncQueueRepository(db!, shopId: widget.shopId),
        gateway: SupabaseSaleUploadGateway(widget.client),
        workerId: uniqueSyncWorkerId('owner-${widget.deviceId}'),
      ).runOnce();
      refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock adjustment saved locally.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stock adjustment could not be saved. Check the quantity and try again.',
            ),
          ),
        );
      }
    }
  }
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({required this.product});
  final InventoryProductRow product;
  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  InventoryMovementType type = InventoryMovementType.manualAdjustment;
  final quantity = TextEditingController(), note = TextEditingController();
  String? error;
  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Adjust ${widget.product.name}'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<InventoryMovementType>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: const [
              DropdownMenuItem(
                value: InventoryMovementType.manualAdjustment,
                child: Text('Manual correction (+ / -)'),
              ),
              DropdownMenuItem(
                value: InventoryMovementType.damage,
                child: Text('Damaged / wastage'),
              ),
              DropdownMenuItem(
                value: InventoryMovementType.openingStock,
                child: Text('Opening stock'),
              ),
            ],
            onChanged: (v) => setState(() => type = v!),
          ),
          TextField(
            controller: quantity,
            decoration: InputDecoration(
              labelText: type == InventoryMovementType.manualAdjustment
                  ? 'Quantity (+ / -)'
                  : 'Quantity',
            ),
          ),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Reason / note *'),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          final raw = quantity.text.trim();
          final negative = raw.startsWith('-');
          final parsed = parseQuantity(negative ? raw.substring(1) : raw);
          final value = parsed == null ? null : (negative ? -parsed : parsed);
          if (value == null ||
              value == 0 ||
              note.text.trim().isEmpty ||
              (type != InventoryMovementType.manualAdjustment && value < 0)) {
            setState(() => error = 'Enter a valid quantity and reason.');
            return;
          }
          Navigator.pop(context, (type, value, note.text.trim()));
        },
        child: const Text('Save Adjustment'),
      ),
    ],
  );
}
