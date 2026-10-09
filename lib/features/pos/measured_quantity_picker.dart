import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/domain/enums.dart';
import '../../core/format/display_format.dart';
import '../../core/format/measure_format.dart';
import '../../core/ui/pos_ui.dart';
import 'pos_state.dart';

/// Result of checking a measured quantity against the shop's rules (U2).
/// [error] blocks the pick; [warning] allows it but tells the cashier.
final class MeasuredPickCheck {
  const MeasuredPickCheck({this.error, this.warning});
  final String? error;
  final String? warning;
  bool get allowed => error == null;
}

/// Checks [quantity] (thousandths) for [product] given what the bill already
/// holds of it ([alreadyInCart]; zero when the line is being set exactly).
/// Mirrors checkout: beyond available stock is refused only when the shop
/// does not allow negative stock and the product tracks stock.
MeasuredPickCheck checkMeasuredPick({
  required PosProduct product,
  required int? quantity,
  required bool allowNegativeStock,
  int alreadyInCart = 0,
}) {
  final invalid = measureQuantityError(quantity);
  if (invalid != null) return MeasuredPickCheck(error: invalid);
  final unit = product.measureUnit!;
  if (product.stockTrackingEnabled &&
      alreadyInCart + quantity! > product.stockQuantity) {
    final left = product.stockQuantity - alreadyInCart;
    final available = formatMeasureQuantity(left < 0 ? 0 : left, unit);
    return allowNegativeStock
        ? MeasuredPickCheck(warning: 'Only $available in stock.')
        : MeasuredPickCheck(error: 'Only $available available.');
  }
  return const MeasuredPickCheck();
}

/// Opens the measured-quantity picker. Returns the thousandths to add, or,
/// with [editing] (the line's current quantity), the exact new quantity.
/// Null when cancelled.
Future<int?> showMeasuredQuantityPicker(
  BuildContext context, {
  required PosProduct product,
  required bool allowNegativeStock,
  int alreadyInCart = 0,
  int? editing,
}) => showDialog<int>(
  context: context,
  builder: (_) => MeasuredQuantityPicker(
    product: product,
    allowNegativeStock: allowNegativeStock,
    alreadyInCart: editing == null ? alreadyInCart : 0,
    editing: editing,
  ),
);

class MeasuredQuantityPicker extends StatefulWidget {
  const MeasuredQuantityPicker({
    super.key,
    required this.product,
    required this.allowNegativeStock,
    this.alreadyInCart = 0,
    this.editing,
  });

  final PosProduct product;
  final bool allowNegativeStock;
  final int alreadyInCart;
  final int? editing;

  @override
  State<MeasuredQuantityPicker> createState() => _MeasuredQuantityPickerState();
}

class _MeasuredQuantityPickerState extends State<MeasuredQuantityPicker> {
  late final MeasureUnit unit = widget.product.measureUnit!;
  late final custom = TextEditingController(
    text: widget.editing == null ? '' : formatDisplayQuantity(widget.editing!),
  );

  /// Typed in g / ml when true, in kg / L when false.
  bool fractionUnit = false;
  bool picked = false;

  List<int> get presets => widget.product.measurePresets.isEmpty
      ? defaultMeasurePresets
      : widget.product.measurePresets;

  int? get typed => parseMeasureInput(custom.text, fractionUnit: fractionUnit);

  MeasuredPickCheck check(int? quantity) => checkMeasuredPick(
    product: widget.product,
    quantity: quantity,
    allowNegativeStock: widget.allowNegativeStock,
    alreadyInCart: widget.alreadyInCart,
  );

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  void _pick(int quantity) {
    // A second tap while the dialog is closing must not pick again.
    if (picked || !check(quantity).allowed) return;
    picked = true;
    Navigator.pop(context, quantity);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final scheme = Theme.of(context).colorScheme;
    final quantity = typed;
    final typedCheck = custom.text.trim().isEmpty ? null : check(quantity);
    final available = product.stockTrackingEnabled
        ? ' • Available ${formatMeasureQuantity(product.stockQuantity < 0 ? 0 : product.stockQuantity, unit)}'
        : '';
    return Theme(
      data: posFormTheme(Theme.of(context)),
      child: AlertDialog(
        title: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 440,
          // Scrolls inside the dialog when the tablet keyboard is open; the
          // POS shell behind it never resizes.
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${measureUnitPriceLabel(formatPkr(product.salePriceMinor), unit)}$available',
                  key: const ValueKey('measure-picker-summary'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                if (widget.editing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'In bill: ${formatMeasureQuantity(widget.editing!, unit)}',
                    ),
                  ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets)
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          key: ValueKey('measure-preset-$preset'),
                          onPressed: check(preset).allowed
                              ? () => _pick(preset)
                              : null,
                          child: Text(formatMeasureQuantity(preset, unit)),
                        ),
                      ),
                  ],
                ),
                if (product.allowCustomQuantity) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Custom quantity',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('measure-custom-input'),
                          controller: custom,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (quantity != null) _pick(quantity);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: true,
                            label: Text(
                              unit.fractionLabel,
                              key: const ValueKey('measure-unit-fraction'),
                            ),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text(
                              unit.wholeLabel,
                              key: const ValueKey('measure-unit-whole'),
                            ),
                          ),
                        ],
                        selected: {fractionUnit},
                        onSelectionChanged: (value) =>
                            setState(() => fractionUnit = value.single),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    quantity == null || quantity <= 0
                        ? 'Total —'
                        : 'Total ${formatPkr(lineTotalMinor(product.salePriceMinor, quantity))}'
                              ' for ${formatMeasureQuantity(quantity, unit)}',
                    key: const ValueKey('measure-live-total'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (typedCheck?.error ?? typedCheck?.warning case final note?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        note,
                        key: const ValueKey('measure-picker-message'),
                        style: TextStyle(
                          color: typedCheck!.allowed
                              ? const Color(0xffb54708)
                              : scheme.error,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (product.allowCustomQuantity)
            FilledButton(
              key: const ValueKey('measure-confirm'),
              onPressed: quantity != null && (typedCheck?.allowed ?? false)
                  ? () => _pick(quantity)
                  : null,
              child: Text(widget.editing == null ? 'Add' : 'Update'),
            ),
        ],
      ),
    );
  }
}
