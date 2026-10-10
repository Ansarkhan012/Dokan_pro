import 'package:flutter/material.dart';
import '../../core/format/display_format.dart';
import '../../core/ui/pos_ui.dart';
import 'pos_state.dart';

/// Whether one more pack of [variant] may be added (U3), mirroring checkout:
/// a tracked size without stock is refused only when the shop does not allow
/// negative stock.
bool canAddPack(
  PosProduct variant, {
  required bool allowNegativeStock,
  int alreadyInCart = 0,
}) =>
    allowNegativeStock ||
    !variant.stockTrackingEnabled ||
    variant.stockQuantity - alreadyInCart >= quantityScale;

/// `24 packs`, `1 pack`.
String packCountLabel(int thousandths) {
  final count = formatDisplayQuantity(thousandths);
  return '$count ${thousandths == quantityScale ? 'pack' : 'packs'}';
}

/// Lets the cashier pick one size of a pack family. Returns the chosen
/// variant (the caller adds exactly one pack of it) or null when cancelled.
Future<PosProduct?> showPackSelector(
  BuildContext context, {
  required String familyName,
  required List<PosProduct> variants,
  required bool allowNegativeStock,
  required int Function(String productId) inCart,
}) => showDialog<PosProduct>(
  context: context,
  builder: (dialogContext) => Theme(
    data: posFormTheme(Theme.of(dialogContext)),
    child: AlertDialog(
      title: Text(familyName, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final variant in variants)
                _PackRow(
                  variant: variant,
                  enabled: canAddPack(
                    variant,
                    allowNegativeStock: allowNegativeStock,
                    alreadyInCart: inCart(variant.id),
                  ),
                  onPick: () => Navigator.pop(dialogContext, variant),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
      ],
    ),
  ),
);

class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.variant,
    required this.enabled,
    required this.onPick,
  });
  final PosProduct variant;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final stock = variant.stockTrackingEnabled
        ? packCountLabel(variant.stockQuantity < 0 ? 0 : variant.stockQuantity)
        : 'Stock not tracked';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variant.packLabel ?? variant.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${formatPkr(variant.salePriceMinor)} • $stock',
                  key: ValueKey('pack-info-${variant.id}'),
                  style: TextStyle(
                    color: variant.isLowStock
                        ? const Color(0xffb42318)
                        : const Color(0xff6c7680),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: ValueKey('pack-pick-${variant.id}'),
              onPressed: enabled ? onPick : null,
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }
}
