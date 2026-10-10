import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/ids/id_generator.dart';
import '../../core/ui/pos_ui.dart';
import 'custom_product_dialog.dart' show moneyField;

/// One editable pack size in the family editor (U3). The product and opening
/// movement ids are minted when the row is added and never change, so a
/// retry after a partial failure re-sends the same ids. [created] rows exist
/// on the server already and are locked.
final class PackRowController {
  PackRowController(IdGenerator ids)
    : productId = ids.next(),
      movementId = ids.next();

  final String productId, movementId;
  final label = TextEditingController(),
      barcode = TextEditingController(),
      sale = TextEditingController(),
      purchase = TextEditingController(),
      opening = TextEditingController(text: '0'),
      low = TextEditingController(text: '0');
  bool created = false;

  void dispose() {
    for (final c in [label, barcode, sale, purchase, opening, low]) {
      c.dispose();
    }
  }
}

/// Whole packs as typed (`24` → 24000 thousandths); null when not a whole,
/// non-negative number. An empty field means zero.
int? parseWholePacks(String input) {
  final text = input.trim();
  if (text.isEmpty) return 0;
  if (!RegExp(r'^\d{1,7}$').hasMatch(text)) return null;
  return int.parse(text) * 1000;
}

/// Touch-friendly list of pack sizes: label, barcode, sale price, cost,
/// opening stock and low-stock level in whole packs, with Add / Remove.
class PackFamilyEditor extends StatelessWidget {
  const PackFamilyEditor({
    super.key,
    required this.rows,
    required this.onAdd,
    required this.onRemove,
    this.locked = false,
  });

  final List<PackRowController> rows;
  final VoidCallback onAdd;
  final ValueChanged<PackRowController> onRemove;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Card(
            key: ValueKey('pack-row-$i'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Pack size ${i + 1}',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (rows[i].created) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Saved',
                          key: ValueKey('pack-row-$i-saved'),
                          style: const TextStyle(color: Color(0xff067647)),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        key: ValueKey('pack-row-$i-remove'),
                        tooltip: 'Remove pack size',
                        onPressed: locked || rows[i].created || rows.length == 1
                            ? null
                            : () => onRemove(rows[i]),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  FieldPair(
                    _text(
                      rows[i].label,
                      'Pack size *',
                      'e.g. 250 g',
                      'pack-row-$i-label',
                      rows[i].created || locked,
                    ),
                    _text(
                      rows[i].barcode,
                      'Barcode',
                      'Optional',
                      'pack-row-$i-barcode',
                      rows[i].created || locked,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FieldPair(
                    _locked(
                      rows[i].created || locked,
                      moneyField(
                        rows[i].sale,
                        'Sale price *',
                        key: ValueKey('pack-row-$i-sale'),
                      ),
                    ),
                    _locked(
                      rows[i].created || locked,
                      moneyField(
                        rows[i].purchase,
                        'Purchase cost',
                        key: ValueKey('pack-row-$i-purchase'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FieldPair(
                    _packs(
                      rows[i].opening,
                      'Opening stock (packs)',
                      'pack-row-$i-opening',
                      rows[i].created || locked,
                    ),
                    _packs(
                      rows[i].low,
                      'Low-stock alert (packs)',
                      'pack-row-$i-low',
                      rows[i].created || locked,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('pack-add-row'),
            onPressed: locked ? null : onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add pack size'),
          ),
        ),
      ],
    );
  }

  Widget _text(
    TextEditingController controller,
    String label,
    String hint,
    String key,
    bool readOnly,
  ) => TextField(
    key: ValueKey(key),
    controller: controller,
    readOnly: readOnly,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _packs(
    TextEditingController controller,
    String label,
    String key,
    bool readOnly,
  ) => TextField(
    key: ValueKey(key),
    controller: controller,
    readOnly: readOnly,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: label),
  );

  Widget _locked(bool readOnly, Widget field) =>
      IgnorePointer(ignoring: readOnly, child: field);
}
