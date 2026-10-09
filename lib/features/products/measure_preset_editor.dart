import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/domain/enums.dart';
import '../../core/format/measure_format.dart';

/// Owner editor for a measured product's quick quantities (U2): chips in
/// ascending order, each removable, plus a typed quantity in g/kg (or ml/L).
/// Keeps between one and [maxMeasurePresets] distinct, valid quantities, so
/// the stored list always satisfies the server's preset rule.
class MeasurePresetEditor extends StatefulWidget {
  const MeasurePresetEditor({
    super.key,
    required this.unit,
    required this.presets,
    required this.onChanged,
  });

  final MeasureUnit unit;
  final List<int> presets;
  final ValueChanged<List<int>> onChanged;

  @override
  State<MeasurePresetEditor> createState() => _MeasurePresetEditorState();
}

class _MeasurePresetEditorState extends State<MeasurePresetEditor> {
  final input = TextEditingController();
  bool fractionUnit = true;
  String? error;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _add() {
    final quantity = parseMeasureInput(input.text, fractionUnit: fractionUnit);
    final invalid = measureQuantityError(quantity);
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    if (widget.presets.contains(quantity)) {
      setState(() => error = 'That quick quantity is already in the list.');
      return;
    }
    if (widget.presets.length >= maxMeasurePresets) {
      setState(
        () => error = 'Use at most $maxMeasurePresets quick quantities.',
      );
      return;
    }
    input.clear();
    setState(() => error = null);
    widget.onChanged([...widget.presets, quantity!]..sort());
  }

  void _remove(int quantity) {
    if (widget.presets.length <= 1) {
      setState(() => error = 'Keep at least one quick quantity.');
      return;
    }
    setState(() => error = null);
    widget.onChanged(widget.presets.where((q) => q != quantity).toList());
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final full = widget.presets.length >= maxMeasurePresets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quantity in widget.presets)
              InputChip(
                key: ValueKey('preset-chip-$quantity'),
                label: Text(formatMeasureQuantity(quantity, unit)),
                onDeleted: () => _remove(quantity),
                deleteButtonTooltipMessage: 'Remove',
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('preset-input'),
                controller: input,
                enabled: !full,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  labelText: full
                      ? 'Quick quantities full ($maxMeasurePresets)'
                      : 'Add quick quantity',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(unit.fractionLabel)),
                ButtonSegment(value: false, label: Text(unit.wholeLabel)),
              ],
              selected: {fractionUnit},
              onSelectionChanged: (value) =>
                  setState(() => fractionUnit = value.single),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('preset-add'),
              tooltip: 'Add',
              onPressed: full ? null : _add,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              key: const ValueKey('preset-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
