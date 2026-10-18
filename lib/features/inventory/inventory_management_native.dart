import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import '../../core/format/display_format.dart';
import '../../core/ids/id_generator.dart';
import '../../core/ui/pos_ui.dart';
import '../pos/product_thumbnail.dart';
import '../../subscription/entitlement_policy.dart';
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
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';
import '../../core/l10n/localized_format.dart';
import '../../core/l10n/messages.dart';

class InventoryManagementScreen extends StatefulWidget {
  const InventoryManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
    this.authorizer,
  });
  final SupabaseClient client;
  final String shopId, deviceId;

  /// Gate for saving financial records; null means the subscription-checked
  /// production authorizer (always, in the app). Tests inject one, as the
  /// local services themselves allow.
  final FinancialMutationAuthorizer? authorizer;
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

  // Block body: returning the Future made setState throw in debug builds,
  // so a saved adjustment was reported as "could not be saved".
  void refresh() => setState(() {
    data = _open();
  });
  @override
  void dispose() {
    search.dispose();
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.ownerNavInventory)),
    body:
        FutureBuilder<(List<InventoryProductRow>, List<InventoryMovementRow>)>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.l10n.inventoryLoadFailed),
                    FilledButton(
                      onPressed: refresh,
                      child: Text(context.l10n.commonTryAgain),
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
                  TabBar(
                    tabs: [
                      Tab(text: context.l10n.inventoryTabCurrent),
                      Tab(text: context.l10n.inventoryTabHistory),
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
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: context.l10n.inventorySearchLabel,
                        ),
                      ),
                    ),
                    SegmentedButton<InventoryFilter>(
                      segments: [
                        ButtonSegment(
                          value: InventoryFilter.all,
                          label: Text(context.l10n.posCategoryAll),
                        ),
                        ButtonSegment(
                          value: InventoryFilter.lowStock,
                          label: Text(context.l10n.inventoryFilterLow),
                        ),
                        ButtonSegment(
                          value: InventoryFilter.outOfStock,
                          label: Text(context.l10n.inventoryFilterOut),
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
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(context.l10n.productsNoMatch)),
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
      ? Center(child: Text(context.l10n.inventoryNoMovements))
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

  bool _adjusting = false;

  Future<void> _adjust(InventoryProductRow product) async {
    final database = db;
    // One adjustment at a time: a second tap on Adjust opens nothing.
    if (database == null || _adjusting) return;
    _adjusting = true;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => InventoryAdjustmentDialog(
          product: product,
          onSave: (type, quantity, note) =>
              LocalInventoryAdjustmentService(
                database,
                const UuidV7Generator(),
                authorizer:
                    widget.authorizer ??
                    productionFinancialMutationAuthorizer(),
              ).record(
                shopId: widget.shopId,
                productId: product.id,
                ownerId: widget.client.auth.currentUser!.id,
                deviceId: widget.deviceId,
                type: type,
                quantity: quantity,
                note: note,
              ),
        ),
      );
      if (saved != true || !mounted) return;
      // Committed locally: stock and history show it now. The upload is best
      // effort (the change is queued) and can never turn this into a failure.
      refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.inventoryAdjustSaved)),
      );
      unawaited(_upload(database));
    } finally {
      _adjusting = false;
    }
  }

  Future<void> _upload(AppDatabase database) async {
    try {
      await SyncWorker(
        queue: SyncQueueRepository(database, shopId: widget.shopId),
        gateway: SupabaseSaleUploadGateway(widget.client),
        workerId: uniqueSyncWorkerId('owner-${widget.deviceId}'),
      ).runOnce();
    } catch (_) {
      // Offline or refused: it stays queued and shows under Sync issues.
    }
  }
}

/// Thousandths typed for a stock adjustment: `20`, `+20`, `-5`, `2.5`
/// (Urdu or Arabic digits too). Null when it is not a number.
int? parseSignedQuantity(String input) {
  var text = normalizeDigits(input).trim();
  var negative = false;
  if (text.startsWith('+')) {
    text = text.substring(1).trimLeft();
  } else if (text.startsWith('-') || text.startsWith('\u2212')) {
    negative = true;
    text = text.substring(1).trimLeft();
  }
  final value = parseQuantity(text);
  if (value == null) return null;
  return negative ? -value : value;
}

/// The first problem with an adjustment the owner typed, or null when it can
/// be saved. Manual correction takes a signed quantity; opening stock and
/// damage take a plain one (damage always removes stock).
String Function(AppLocalizations)? adjustmentInputError({
  required InventoryMovementType type,
  required String quantity,
  required String note,
  required bool measured,
}) {
  if (quantity.trim().isEmpty) {
    return (l10n) => l10n.inventoryErrQuantityMissing;
  }
  final value = parseSignedQuantity(quantity);
  if (value == null) return (l10n) => l10n.inventoryErrQuantityFormat;
  if (value == 0) return (l10n) => l10n.inventoryErrQuantityZero;
  if (value < 0 && type != InventoryMovementType.manualAdjustment) {
    return (l10n) => l10n.inventoryErrQuantitySign;
  }
  if (!measured && value % 1000 != 0) {
    return (l10n) => l10n.inventoryErrWholeUnits;
  }
  if (note.trim().isEmpty) return (l10n) => l10n.inventoryErrReasonRequired;
  return null;
}

/// Why the service refused an adjustment, in the owner's language.
String Function(AppLocalizations) _adjustmentRefusal(Object error) {
  final message = switch (error) {
    ArgumentError(:final message) => '$message',
    StateError(:final message) => message,
    SubscriptionMutationBlocked(:final message) => message,
    _ => null,
  };
  return switch (message) {
    'Quantity cannot be zero.' => (l10n) => l10n.inventoryErrQuantityZero,
    'Quantity must be positive for this adjustment.' =>
      (l10n) => l10n.inventoryErrQuantitySign,
    'A reason is required.' => (l10n) => l10n.inventoryErrReasonRequired,
    'Piece products are adjusted in whole units.' =>
      (l10n) => l10n.inventoryErrWholeUnits,
    'This adjustment would make stock negative.' =>
      (l10n) => l10n.inventoryErrWouldGoNegative,
    final String text when error is SubscriptionMutationBlocked =>
      (l10n) => localizedMessage(l10n, text),
    _ => (l10n) => l10n.inventoryAdjustFailed,
  };
}

/// Records one stock adjustment. [onSave] runs once per Save (the button is
/// locked while it runs); the dialog closes with `true` only after it
/// succeeds, and shows the actual problem when it is refused.
class InventoryAdjustmentDialog extends StatefulWidget {
  const InventoryAdjustmentDialog({
    super.key,
    required this.product,
    required this.onSave,
  });
  final InventoryProductRow product;
  final Future<void> Function(
    InventoryMovementType type,
    int quantity,
    String note,
  )
  onSave;
  @override
  State<InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState extends State<InventoryAdjustmentDialog> {
  InventoryMovementType type = InventoryMovementType.manualAdjustment;
  final quantity = TextEditingController(), note = TextEditingController();
  bool saving = false;

  /// Resolved when shown, so a language switch also translates it.
  String Function(AppLocalizations)? error;
  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    final problem = adjustmentInputError(
      type: type,
      quantity: quantity.text,
      note: note.text,
      measured: widget.product.measured,
    );
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        type,
        parseSignedQuantity(quantity.text)!,
        note.text.trim(),
      );
    } catch (e) {
      // Nothing was written: the service checks before its transaction ends.
      if (mounted) {
        setState(() {
          saving = false;
          error = _adjustmentRefusal(e);
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        // Scrolls above the soft keyboard; the actions stay visible.
        scrollable: true,
        title: Text(
          l10n.inventoryAdjustTitle(
            productDisplayName(
              context,
              widget.product.name,
              productId: widget.product.id,
            ),
          ),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<InventoryMovementType>(
                initialValue: type,
                decoration: InputDecoration(labelText: l10n.inventoryReason),
                items: [
                  DropdownMenuItem(
                    value: InventoryMovementType.manualAdjustment,
                    child: Text(l10n.inventoryManualCorrection),
                  ),
                  DropdownMenuItem(
                    value: InventoryMovementType.damage,
                    child: Text(l10n.movementDamage),
                  ),
                  DropdownMenuItem(
                    value: InventoryMovementType.openingStock,
                    child: Text(l10n.movementOpening),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (v) => setState(() {
                        type = v!;
                        error = null;
                      }),
              ),
              TextField(
                key: const ValueKey('adjust-quantity'),
                controller: quantity,
                enabled: !saving,
                textDirection: TextDirection.ltr,
                inputFormatters: const [AsciiDigitsFormatter()],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: type == InventoryMovementType.manualAdjustment
                      ? l10n.inventoryQuantitySigned
                      : l10n.measureQuantityLabel,
                ),
              ),
              TextField(
                key: const ValueKey('adjust-note'),
                controller: note,
                enabled: !saving,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => save(),
                decoration: InputDecoration(
                  labelText: l10n.inventoryReasonNote,
                ),
              ),
              if (error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error(l10n),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('adjust-save'),
            onPressed: saving ? null : save,
            child: Text(
              saving ? l10n.inventorySaving : l10n.inventorySaveAdjustment,
            ),
          ),
        ],
      ),
    );
  }
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
    final l10n = context.l10n;
    final secondary = [
      l10n.unitName(p.unit, humanizeIdentifier(p.unit)),
      p.barcode == null ? l10n.posNoBarcode : bidiId(context, p.barcode!),
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
                  productDisplayName(context, p.name, productId: p.id),
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
                bidiQuantity(context, formatDisplayQuantity(p.stockQuantity)),
                key: ValueKey('stock-${p.id}'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: stockColor,
                ),
              ),
              if (p.isOutOfStock)
                StatusPill(l10n.inventoryOutOfStock, tone: StatusTone.danger)
              else if (p.isLowStock)
                StatusPill(l10n.posLowStock, tone: StatusTone.warning)
              else
                Text(
                  l10n.inventoryInStock,
                  style: const TextStyle(color: posMuted, fontSize: 12),
                ),
              if (!p.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: StatusPill(
                    l10n.productsInactive,
                    tone: StatusTone.neutral,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            onPressed: onAdjust,
            style: OutlinedButton.styleFrom(minimumSize: const Size(88, 44)),
            child: Text(l10n.inventoryAdjust),
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

/// [inventoryMovementLabel] in the UI language.
String localizedInventoryMovementLabel(
  AppLocalizations l10n,
  InventoryMovementType type, {
  String? referenceType,
}) => switch (type) {
  InventoryMovementType.openingStock => l10n.movementOpening,
  InventoryMovementType.purchase => l10n.movementPurchase,
  InventoryMovementType.sale => l10n.movementSale,
  InventoryMovementType.returnIn =>
    referenceType == 'sale_void' ? l10n.movementVoid : l10n.movementReturn,
  InventoryMovementType.damage => l10n.movementDamage,
  InventoryMovementType.manualAdjustment => l10n.movementAdjustment,
  InventoryMovementType.stockCorrection => l10n.movementCorrection,
};

class InventoryMovementTile extends StatelessWidget {
  const InventoryMovementTile({super.key, required this.movement});
  final InventoryMovementRow movement;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final l10n = context.l10n;
    final label = localizedInventoryMovementLabel(
      l10n,
      m.type,
      referenceType: m.referenceType,
    );
    final details = [
      label,
      if (m.reference != null) bidiId(context, m.reference!),
      // `5 Oct 2026, 1:17 PM`; Urdu uses its own comma.
      l10n.dateWithTime(
        localizedDate(l10n, m.createdAt),
        localizedTime(l10n, m.createdAt),
      ),
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
                  productDisplayName(context, m.productName),
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
                    bidiName(context, note),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            bidiQuantity(context, formatSignedQuantity(m.quantity)),
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
