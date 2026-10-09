import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/domain/enums.dart';
import '../../core/errors/safe_error_message.dart';
import '../../core/format/measure_format.dart';
import '../../core/images/product_image_processing.dart';
import '../../core/ui/pos_ui.dart';
import '../pos/pos_state.dart' show parseMoneyMinor, minorToInput;
import 'custom_product_dialog.dart';
import 'measure_preset_editor.dart';
import 'product_image_picker.dart';
import 'product_management_models.dart';
import 'product_management_native.dart' show parseQuantity, quantityToInput;

/// Validated edits. Prices, threshold and activation go through the existing
/// online product update; the image change is applied only to the local,
/// device-owned image store.
final class ProductEdit {
  const ProductEdit({
    required this.purchasePriceMinor,
    required this.salePriceMinor,
    required this.lowStockLevel,
    required this.isActive,
    this.newImage,
    this.removeImage = false,
    this.measurePresets,
    this.allowCustomQuantity,
  });
  final int purchasePriceMinor, salePriceMinor, lowStockLevel;
  final bool isActive;

  /// U2, measured products only (null for a piece product): the quick
  /// quantities and custom-quantity switch. Selling mode, unit and stock are
  /// never part of an edit.
  final List<int>? measurePresets;
  final bool? allowCustomQuantity;
  final Uint8List? newImage;
  final bool removeImage;
}

typedef ProductEditSubmitter = Future<void> Function(ProductEdit edit);

class EditProductDialog extends StatefulWidget {
  const EditProductDialog({
    super.key,
    required this.product,
    required this.onSubmit,
    this.existingImage,
    this.picker = const GalleryProductImagePicker(),
    this.prepareImage = prepareProductThumbnailInBackground,
  });

  final ManagedProduct product;
  final ProductEditSubmitter onSubmit;

  /// The product's current local image, if any.
  final File? existingImage;
  final ProductImagePicker picker;
  final ProductImagePreparer prepareImage;

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  late final purchase = TextEditingController(
    text: minorToInput(widget.product.purchasePriceMinor),
  );
  late final sale = TextEditingController(
    text: minorToInput(widget.product.salePriceMinor),
  );
  late final low = TextEditingController(
    text: quantityToInput(widget.product.lowStockLevel ?? 0),
  );
  late bool active = widget.product.isActive;
  late final MeasureUnit? measure = widget.product.measureUnit;
  late List<int> presets =
      widget.product.measurePresets ?? [...defaultMeasurePresets];
  late bool allowCustomQuantity = widget.product.allowCustomQuantity;
  Uint8List? newImage;
  bool removeImage = false;
  bool processingImage = false, saving = false;
  String? imageError, error;

  String get _per => measure == null ? '' : ' per ${measure!.wholeLabel}';

  @override
  void dispose() {
    purchase.dispose();
    sale.dispose();
    low.dispose();
    super.dispose();
  }

  ImageProvider? get _preview {
    final picked = newImage;
    if (picked != null) return MemoryImage(picked);
    final existing = widget.existingImage;
    if (!removeImage && existing != null) return FileImage(existing);
    return null;
  }

  Future<void> _chooseImage() async {
    if (processingImage || saving) return;
    setState(() {
      processingImage = true;
      imageError = null;
    });
    try {
      final picked = await widget.picker.pick();
      if (picked == null) return;
      final prepared = await widget.prepareImage(picked);
      if (mounted) {
        setState(() {
          newImage = prepared;
          removeImage = false;
        });
      }
    } on ProductImageException catch (e) {
      if (mounted) setState(() => imageError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => imageError = 'Could not open that image. Try another.');
      }
    } finally {
      if (mounted) setState(() => processingImage = false);
    }
  }

  void _removeImage() => setState(() {
    newImage = null;
    removeImage = widget.existingImage != null;
    imageError = null;
  });

  Future<void> _submit() async {
    if (saving || processingImage) return;
    final purchaseMinor = parseMoneyMinor(purchase.text);
    final saleMinor = parseMoneyMinor(sale.text);
    final lowQuantity = parseQuantity(low.text);
    if (purchaseMinor == null || saleMinor == null || lowQuantity == null) {
      setState(() => error = 'Enter valid non-negative values.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSubmit(
        ProductEdit(
          purchasePriceMinor: purchaseMinor,
          salePriceMinor: saleMinor,
          lowStockLevel: lowQuantity,
          isActive: active,
          newImage: newImage,
          removeImage: removeImage,
          measurePresets: measure == null ? null : presets,
          allowCustomQuantity: measure == null ? null : allowCustomQuantity,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = safeUserMessage(e, fallback: 'Could not update product.');
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    title: 'Edit product',
    subtitle: widget.product.name,
    maxWidth: 760,
    locked: saving,
    message: error == null
        ? null
        : Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
    body: (context, wide) {
      final imageCard = ProductImagePickerCard(
        image: _preview,
        busy: processingImage,
        error: imageError,
        onChoose: _chooseImage,
        onRemove: _removeImage,
      );
      final fields = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSectionLabel('Pricing & stock'),
          if (measure case final unit?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                unit == MeasureUnit.kg
                    ? 'Loose product · sold by weight (kg)'
                    : 'Loose product · sold by volume (L)',
                key: const ValueKey('edit-product-measure'),
              ),
            ),
          FieldPair(
            moneyField(
              purchase,
              'Purchase price$_per',
              key: const ValueKey('edit-product-purchase'),
            ),
            moneyField(
              sale,
              'Sale price$_per',
              key: const ValueKey('edit-product-sale'),
            ),
          ),
          const SizedBox(height: 12),
          quantityField(
            low,
            'Low-stock alert at${measure == null ? '' : ' (${measure!.wholeLabel})'}',
            key: const ValueKey('edit-product-low'),
            onSubmitted: measure == null ? _submit : null,
          ),
          if (measure case final unit?) ...[
            const SizedBox(height: 16),
            const FormSectionLabel('Quick quantities'),
            MeasurePresetEditor(
              key: const ValueKey('edit-product-presets'),
              unit: unit,
              presets: presets,
              onChanged: (value) => setState(() => presets = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('edit-product-allow-custom'),
              contentPadding: EdgeInsets.zero,
              value: allowCustomQuantity,
              onChanged: (value) => setState(() => allowCustomQuantity = value),
              title: const Text('Allow custom quantity'),
            ),
          ],
          const SizedBox(height: 16),
          const FormSectionLabel('Availability'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: active,
            onChanged: (value) => setState(() => active = value),
            title: const Text('Active'),
            subtitle: const Text('Inactive products are hidden from sale.'),
          ),
        ],
      );
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 200, child: imageCard),
            const SizedBox(width: 24),
            Expanded(child: fields),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: SizedBox(width: 180, child: imageCard)),
          const SizedBox(height: 20),
          fields,
        ],
      );
    },
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('edit-product-save'),
        onPressed: processingImage || saving ? null : _submit,
        child: Text(saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}

/// Asks before creating a product that looks like one the shop already has.
/// Returns true only when the owner chooses to create it anyway.
Future<bool> confirmPossibleDuplicate(
  BuildContext context,
  List<({String name, bool sameBarcode})> matches,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.content_copy_outlined),
      title: const Text('This product may already exist'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your shop already has:'),
            const SizedBox(height: 8),
            for (final match in matches.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${match.name}'
                  '${match.sameBarcode ? '  (same barcode)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (matches.length > 5) Text('and ${matches.length - 5} more'),
            const SizedBox(height: 12),
            const Text(
              'Creating it again makes a separate product with its own '
              'stock. Go back to edit, or create it anyway.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Go back'),
        ),
        FilledButton(
          key: const ValueKey('duplicate-create-anyway'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Create anyway'),
        ),
      ],
    ),
  );
  return result == true;
}
