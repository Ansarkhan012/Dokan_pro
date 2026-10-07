import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import '../../core/format/display_format.dart';
import '../../core/ids/id_generator.dart';
import '../../core/ui/pos_ui.dart';
import '../pos/product_thumbnail.dart';
import '../../subscription/subscription_runtime.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/sync_health.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_worker.dart';
import '../products/product_management_native.dart' show parseQuantity;
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
    body:
        FutureBuilder<(List<InventoryProductRow>, List<InventoryMovementRow>)>(
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
                      children: [_stockTab(products), _historyTab(history)],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
  );

  /// Horizontal padding that keeps rows readable on wide tablets instead of
  /// stretching name and stock to opposite screen edges.
  static double _side(double width) => width > 1032 ? (width - 1000) / 2 : 16;

  Widget _stockTab(List<InventoryProductRow> products) => LayoutBuilder(
    builder: (context, constraints) {
      final side = _side(constraints.maxWidth);
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 16, side, 8),
            sliver: SliverToBoxAdapter(
              child: Theme(
                data: posFormTheme(Theme.of(context)),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: search,
                        textInputAction: TextInputAction.search,
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
            ),
          ),
          if (products.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No products match this filter.')),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 4, side, 20),
              sliver: SliverList.separated(
                itemCount: products.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => InventoryStockRow(
                  product: products[i],
                  onAdjust: () => _adjust(products[i]),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _historyTab(List<InventoryMovementRow> history) => history.isEmpty
      ? const Center(child: Text('No stock movements yet.'))
      : LayoutBuilder(
          builder: (context, constraints) {
            final side = _side(constraints.maxWidth);
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(side, 16, side, 20),
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) =>
                  InventoryMovementTile(movement: history[i]),
            );
          },
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

/// One Current Stock row: identity on the left, stock and Adjust together on
/// the right so the action sits next to the number it changes.
class InventoryStockRow extends StatelessWidget {
  const InventoryStockRow({
    super.key,
    required this.product,
    required this.onAdjust,
  });
  final InventoryProductRow product;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final secondary = [
      humanizeIdentifier(p.unit),
      p.barcode ?? 'No barcode',
    ].join(' • ');
    final stockColor = p.isOutOfStock
        ? StatusPill.colorFor(StatusTone.danger)
        : p.isLowStock
        ? StatusPill.colorFor(StatusTone.warning)
        : null;
    return PosCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          ProductThumbnail(
            imagePath: p.imagePath,
            productId: p.id,
            width: 48,
            height: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: posMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatDisplayQuantity(p.stockQuantity),
                key: ValueKey('stock-${p.id}'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: stockColor,
                ),
              ),
              if (p.isOutOfStock)
                const StatusPill('Out of stock', tone: StatusTone.danger)
              else if (p.isLowStock)
                const StatusPill('Low stock', tone: StatusTone.warning)
              else
                const Text(
                  'in stock',
                  style: TextStyle(color: posMuted, fontSize: 12),
                ),
              if (!p.isActive)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: StatusPill('Inactive', tone: StatusTone.neutral),
                ),
            ],
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            onPressed: onAdjust,
            style: OutlinedButton.styleFrom(minimumSize: const Size(88, 44)),
            child: const Text('Adjust'),
          ),
        ],
      ),
    );
  }
}

/// Owner-facing name of a stock movement. Voids are stored as `returnIn`
/// movements referencing a `sale_void`, so the reference decides the label.
String inventoryMovementLabel(
  InventoryMovementType type, {
  String? referenceType,
}) => switch (type) {
  InventoryMovementType.openingStock => 'Opening stock',
  InventoryMovementType.purchase => 'Purchase',
  InventoryMovementType.sale => 'Sale',
  InventoryMovementType.returnIn =>
    referenceType == 'sale_void' ? 'Void' : 'Return',
  InventoryMovementType.damage => 'Damaged / wastage',
  InventoryMovementType.manualAdjustment => 'Adjustment',
  InventoryMovementType.stockCorrection => 'Stock correction',
};

class InventoryMovementTile extends StatelessWidget {
  const InventoryMovementTile({super.key, required this.movement});
  final InventoryMovementRow movement;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final label = inventoryMovementLabel(
      m.type,
      referenceType: m.referenceType,
    );
    final details = [
      label,
      if (m.reference != null) m.reference!,
      formatDisplayDateTime(m.createdAt, separator: ', '),
    ].join(' • ');
    final note = m.note?.trim();
    final incoming = m.quantity > 0;
    return PosCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  style: const TextStyle(color: posMuted, fontSize: 13),
                ),
                if (note != null && note.isNotEmpty)
                  Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatSignedQuantity(m.quantity),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: m.quantity == 0
                  ? posMuted
                  : incoming
                  ? StatusPill.colorFor(StatusTone.success)
                  : StatusPill.colorFor(StatusTone.danger),
            ),
          ),
        ],
      ),
    );
  }
}
