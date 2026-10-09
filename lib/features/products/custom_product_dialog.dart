import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/domain/enums.dart';
import '../../core/errors/safe_error_message.dart';
import '../../core/format/measure_format.dart';
import '../../core/images/product_image_processing.dart';
import '../../core/ui/pos_ui.dart';
import '../pos/pos_state.dart' show parseMoneyMinor;
import 'measure_preset_editor.dart';
import 'product_image_picker.dart';
import 'product_management_models.dart';
import 'product_management_native.dart' show parseQuantity;

/// What the Create Custom Product dialog returns: the synced product input
/// plus an optional, already-compressed local thumbnail.
final class CustomProductDraft {
  const CustomProductDraft({required this.input, this.image});
  final CustomProductInput input;
  final Uint8List? image;
}

typedef ProductImagePreparer = Future<Uint8List> Function(Uint8List source);

/// Persists a validated draft. While it runs the dialog stays open and
/// locked; if it throws, the dialog shows the error and keeps everything the
/// shopkeeper entered, including the chosen image.
typedef CustomProductSubmitter = Future<void> Function(CustomProductDraft);

/// Thrown by a [CustomProductSubmitter] when the owner chose to go back and
/// edit (for example after a duplicate warning): the dialog simply unlocks.
final class CustomProductSubmitCancelled implements Exception {
  const CustomProductSubmitCancelled();
}

class CustomProductDialog extends StatefulWidget {
  const CustomProductDialog({
    super.key,
    required this.categories,
    this.picker = const GalleryProductImagePicker(),
    this.prepareImage = prepareProductThumbnailInBackground,
    this.onSubmit,
  });

  final List<ProductCategory> categories;
  final ProductImagePicker picker;
  final ProductImagePreparer prepareImage;
  final CustomProductSubmitter? onSubmit;

  @override
  State<CustomProductDialog> createState() => _CustomProductDialogState();
}

class _CustomProductDialogState extends State<CustomProductDialog> {
  final name = TextEditingController(),
      barcode = TextEditingController(),
      pack = TextEditingController(),
      purchase = TextEditingController(),
      sale = TextEditingController(),
      opening = TextEditingController(text: '0'),
      low = TextEditingController(text: '0');
  String? categoryId;
  ProductUnit unit = ProductUnit.piece;

  // U2: a loose product is sold by weight or volume, priced per kg / L.
  SellMode sellMode = SellMode.piece;
  MeasureUnit measure = MeasureUnit.kg;
  List<int> presets = [...defaultMeasurePresets];
  bool allowCustomQuantity = true;
  bool get loose => sellMode == SellMode.measured;
  Uint8List? image;
  bool processingImage = false;
  bool saving = false;
  String? imageError;
  String? error;

  @override
  void dispose() {
    for (final c in [name, barcode, pack, purchase, sale, opening, low]) {
      c.dispose();
    }
    super.dispose();
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
      if (mounted) setState(() => image = prepared);
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
    image = null;
    imageError = null;
  });

  Future<void> _submit() async {
    if (saving || processingImage) return;
    final p = parseMoneyMinor(purchase.text),
        s = parseMoneyMinor(sale.text),
        o = parseQuantity(opening.text),
        l = parseQuantity(low.text);
    if (name.text.trim().isEmpty ||
        categoryId == null ||
        p == null ||
        s == null ||
        o == null ||
        l == null) {
      setState(() => error = 'Complete all required fields with valid values.');
      return;
    }
    final draft = CustomProductDraft(
      input: CustomProductInput(
        name: name.text.trim(),
        categoryId: categoryId!,
        unit: loose
            ? (measure == MeasureUnit.kg ? ProductUnit.kg : ProductUnit.liter)
            : unit,
        barcode: barcode.text.trim().isEmpty ? null : barcode.text.trim(),
        packLabel: loose || pack.text.trim().isEmpty ? null : pack.text.trim(),
        purchasePriceMinor: p,
        salePriceMinor: s,
        openingQuantity: o,
        lowStockLevel: l,
        sellMode: sellMode,
        measurePresets: loose ? presets : null,
        allowCustomQuantity: loose ? allowCustomQuantity : true,
      ),
      image: image,
    );
    final submit = widget.onSubmit;
    if (submit != null) {
      setState(() {
        saving = true;
        error = null;
      });
      try {
        await submit(draft);
      } on CustomProductSubmitCancelled {
        if (mounted) setState(() => saving = false);
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            saving = false;
            error = safeUserMessage(
              e,
              fallback: 'Could not create the product. Please try again.',
            );
          });
        }
        return;
      }
    }
    if (mounted) Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    title: 'Create Custom Product',
    subtitle: 'For items that are not in the master catalog.',
    locked: saving,
    message: formFooterMessage(context, error),
    body: (context, wide) => _body(wide),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('custom-product-create'),
        onPressed: processingImage || saving ? null : _submit,
        child: Text(saving ? 'Creating…' : 'Create Product'),
      ),
    ],
  );

  Widget _body(bool wide) {
    final bytes = image;
    final imageCard = ProductImagePickerCard(
      image: bytes == null ? null : MemoryImage(bytes),
      busy: processingImage,
      error: imageError,
      onChoose: _chooseImage,
      onRemove: _removeImage,
    );
    final fields = _fields();
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 220, child: imageCard),
          const SizedBox(width: 24),
          Expanded(child: fields),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: SizedBox(width: 200, child: imageCard)),
        const SizedBox(height: 20),
        fields,
      ],
    );
  }

  Widget _fields() {
    final per = loose ? ' per ${measure.wholeLabel}' : '';
    final stockUnit = loose ? ' (${measure.wholeLabel})' : '';
    final barcodeField = TextField(
      key: const ValueKey('custom-product-barcode'),
      controller: barcode,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Barcode',
        hintText: 'Optional',
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSectionLabel('Product details'),
        SegmentedButton<SellMode>(
          key: const ValueKey('custom-product-selling-type'),
          segments: const [
            ButtonSegment(
              value: SellMode.piece,
              icon: Icon(Icons.inventory_2_outlined),
              label: Text('Piece', key: ValueKey('selling-piece')),
            ),
            ButtonSegment(
              value: SellMode.measured,
              icon: Icon(Icons.scale_outlined),
              label: Text('Loose / Measured', key: ValueKey('selling-loose')),
            ),
          ],
          selected: {sellMode},
          onSelectionChanged: saving
              ? null
              : (value) => setState(() => sellMode = value.single),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('custom-product-name'),
          controller: name,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Product name *'),
        ),
        const SizedBox(height: 12),
        FieldPair(
          DropdownButtonFormField<String>(
            key: const ValueKey('custom-product-category'),
            initialValue: categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category *'),
            items: widget.categories
                .map(
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => categoryId = v),
          ),
          loose
              ? SegmentedButton<MeasureUnit>(
                  key: const ValueKey('custom-product-measure'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: MeasureUnit.kg,
                      label: Text('Weight (kg)', key: ValueKey('measure-kg')),
                    ),
                    ButtonSegment(
                      value: MeasureUnit.liter,
                      label: Text('Volume (L)', key: ValueKey('measure-liter')),
                    ),
                  ],
                  selected: {measure},
                  onSelectionChanged: (value) =>
                      setState(() => measure = value.single),
                )
              : DropdownButtonFormField<ProductUnit>(
                  initialValue: unit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Unit *'),
                  items: ProductUnit.values
                      .map(
                        (u) => DropdownMenuItem(value: u, child: Text(u.label)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => unit = v!),
                ),
        ),
        const SizedBox(height: 12),
        if (loose)
          barcodeField
        else
          FieldPair(
            barcodeField,
            TextField(
              controller: pack,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Pack size / label',
                hintText: 'e.g. 500 g',
              ),
            ),
          ),
        const SizedBox(height: 24),
        const FormSectionLabel('Pricing & stock'),
        FieldPair(
          moneyField(
            purchase,
            'Purchase price$per *',
            key: const ValueKey('custom-product-purchase'),
          ),
          moneyField(
            sale,
            'Sale price$per *',
            key: const ValueKey('custom-product-sale'),
          ),
        ),
        const SizedBox(height: 12),
        FieldPair(
          quantityField(
            opening,
            'Opening stock$stockUnit',
            key: const ValueKey('custom-product-opening'),
          ),
          quantityField(
            low,
            'Low-stock alert at$stockUnit',
            key: const ValueKey('custom-product-low'),
            onSubmitted: loose ? null : _submit,
          ),
        ),
        if (loose) ...[
          const SizedBox(height: 24),
          const FormSectionLabel('Quick quantities'),
          MeasurePresetEditor(
            key: const ValueKey('custom-product-presets'),
            unit: measure,
            presets: presets,
            onChanged: (value) => setState(() => presets = value),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('custom-product-allow-custom'),
            contentPadding: EdgeInsets.zero,
            value: allowCustomQuantity,
            onChanged: (value) => setState(() => allowCustomQuantity = value),
            title: const Text('Allow custom quantity'),
            subtitle: const Text(
              'Cashier may type any amount, not only quick quantities.',
            ),
          ),
        ],
      ],
    );
  }
}

/// Numeric money input shared by Create and Edit product.
Widget moneyField(
  TextEditingController controller,
  String label, {
  Key? key,
  VoidCallback? onSubmitted,
}) => _numberField(
  controller,
  label,
  key: key,
  prefix: 'Rs ',
  onSubmitted: onSubmitted,
);

/// Numeric quantity input shared by Create and Edit product.
Widget quantityField(
  TextEditingController controller,
  String label, {
  Key? key,
  VoidCallback? onSubmitted,
}) => _numberField(controller, label, key: key, onSubmitted: onSubmitted);

Widget _numberField(
  TextEditingController controller,
  String label, {
  Key? key,
  String? prefix,
  VoidCallback? onSubmitted,
}) => TextField(
  key: key,
  controller: controller,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
  textInputAction: onSubmitted == null
      ? TextInputAction.next
      : TextInputAction.done,
  onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
  decoration: InputDecoration(labelText: label, prefixText: prefix),
);

/// Square product photo card: empty state invites a choice; once chosen it
/// previews the image with Change / Remove. Never shows a path or URL.
class ProductImagePickerCard extends StatelessWidget {
  const ProductImagePickerCard({
    super.key,
    required this.image,
    required this.busy,
    required this.onChoose,
    required this.onRemove,
    this.error,
  });

  final ImageProvider? image;
  final bool busy;
  final String? error;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bytes = image;
    final frame = Semantics(
      button: true,
      label: bytes == null ? null : 'Change product image',
      child: AspectRatio(
        aspectRatio: 1,
        child: Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('product-image-choose'),
            onTap: busy ? null : onChoose,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (bytes != null)
                  Image(
                    image: bytes,
                    key: const ValueKey('product-image-preview'),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    semanticLabel: 'Product image preview',
                    errorBuilder: (_, _, _) => const _EmptyImageHint(),
                  )
                else
                  const _EmptyImageHint(),
                if (busy)
                  ColoredBox(
                    color: scheme.surface.withValues(alpha: 0.7),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Product image',
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        frame,
        const SizedBox(height: 10),
        if (bytes == null)
          Text(
            'Optional · JPG, PNG or WebP',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('product-image-change'),
                onPressed: busy ? null : onChoose,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Change'),
              ),
              TextButton.icon(
                key: const ValueKey('product-image-remove'),
                onPressed: busy ? null : onRemove,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
              ),
            ],
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );
  }
}

class _EmptyImageHint extends StatelessWidget {
  const _EmptyImageHint();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 44,
              color: scheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose product image',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
