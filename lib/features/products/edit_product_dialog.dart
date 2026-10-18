import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/domain/enums.dart';
import '../../core/errors/safe_error_message.dart';
import '../../core/format/display_format.dart' show humanizeIdentifier;
import '../../core/format/measure_format.dart';
import '../../core/images/product_image_processing.dart';
import '../../core/ui/pos_ui.dart';
import '../pos/pos_state.dart' show parseMoneyMinor, minorToInput;
import 'custom_product_dialog.dart';
import 'measure_preset_editor.dart';
import 'product_image_picker.dart';
import 'product_management_models.dart';
import 'product_management_service.dart';
import 'product_management_native.dart'
    show categoryLabel, parseQuantity, quantityToInput;
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';
import '../../core/l10n/localized_format.dart';
import '../../core/l10n/messages.dart';

export 'product_management_models.dart' show ProductEdit;

typedef ProductEditSubmitter = Future<void> Function(ProductEdit edit);

/// Edit Product: the same fields and widgets as Create Product, prefilled
/// with the product's current values. Selling mode and stock are not edited
/// here: stock changes only through [onAdjustStock] (a recorded stock
/// adjustment), and the unit is fixed once the product has stock history.
class EditProductDialog extends StatefulWidget {
  const EditProductDialog({
    super.key,
    required this.product,
    required this.onSubmit,
    this.existingImage,
    this.picker = const GalleryProductImagePicker(),
    this.prepareImage = prepareProductThumbnailInBackground,
    this.categories = const [],
    this.barcodeOwners = const {},
    this.familySizes = const [],
    this.onAdjustStock,
    this.onDelete,
  });

  final ManagedProduct product;
  final ProductEditSubmitter onSubmit;

  /// The product's current local image, if any.
  final File? existingImage;
  final ProductImagePicker picker;
  final ProductImagePreparer prepareImage;

  /// The shop's categories; the category can be changed when given.
  final List<ProductCategory> categories;

  /// Barcodes in use in the shop and the product id using each.
  final Map<String, String> barcodeOwners;

  /// Pack labels of the family's other sizes (a pack variant only).
  final List<String> familySizes;

  /// Opens the recorded stock adjustment; returns the new stock, or null
  /// when nothing was saved.
  final Future<int?> Function()? onAdjustStock;

  /// Owner only: archives the product after confirmation; true when done.
  /// Nothing is ever deleted (the server grants no delete).
  final Future<bool> Function()? onDelete;

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  ManagedProduct get product => widget.product;
  late final name = TextEditingController(text: product.editableName);
  late final barcode = TextEditingController(text: product.barcode ?? '');
  late final pack = TextEditingController(text: product.packLabel ?? '');
  late final purchase = TextEditingController(
    text: minorToInput(product.purchasePriceMinor),
  );
  late final sale = TextEditingController(
    text: minorToInput(product.salePriceMinor),
  );
  late final low = TextEditingController(
    text: quantityToInput(product.lowStockLevel ?? 0),
  );
  late String? categoryId =
      widget.categories.any((c) => c.id == product.categoryId)
      ? product.categoryId
      : null;
  late final ProductUnit? storedUnit = ProductUnit.values
      .where((u) => u.name == product.unit.toLowerCase())
      .firstOrNull;
  late ProductUnit? unit = storedUnit;
  late bool active = product.isActive;
  late final MeasureUnit? measure = product.measureUnit;
  late List<int> presets = product.measurePresets ?? [...defaultMeasurePresets];
  late bool allowCustomQuantity = product.allowCustomQuantity;
  late int stock = product.stockQuantity;
  Uint8List? newImage;
  bool removeImage = false;
  bool processingImage = false, saving = false, busy = false;
  String? imageError, error;

  bool get _variant => product.familyId != null;

  /// A pack size's name and category belong to its whole family; changing
  /// them needs one atomic server update for every size, which does not
  /// exist yet, so they are shown but not editable.
  bool get _sharedLocked => _variant;

  /// The unit relabels every recorded quantity, so it changes only while
  /// there is none, and only between counting units.
  bool get _unitEditable =>
      measure == null &&
      !_variant &&
      product.movementCount == 0 &&
      storedUnit != null &&
      _countUnits.contains(storedUnit);

  static const _countUnits = [
    ProductUnit.piece,
    ProductUnit.pack,
    ProductUnit.bottle,
    ProductUnit.carton,
    ProductUnit.dozen,
  ];

  @override
  void dispose() {
    for (final c in [name, barcode, pack, purchase, sale, low]) {
      c.dispose();
    }
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

  /// The first problem with the identity fields, as an English message the
  /// footer translates; null when they are valid.
  String? _identityProblem() {
    if (name.text.trim().isEmpty) return 'Product name is required';
    if (!_sharedLocked &&
        widget.categories.isNotEmpty &&
        product.isCustom &&
        categoryId == null) {
      return 'Category is required';
    }
    final code = barcode.text.trim();
    if (code.isNotEmpty) {
      final owner = widget.barcodeOwners[code];
      if (owner != null && owner != product.id) {
        return 'Barcode $code is already used in this shop';
      }
    }
    if (_variant) {
      final label = pack.text.trim();
      if (label.isEmpty) return 'Every pack needs a size label';
      String key(String value) =>
          value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (widget.familySizes.any((other) => key(other) == key(label))) {
        return 'Pack size $label is listed twice';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (saving || processingImage || busy) return;
    final purchaseMinor = parseMoneyMinor(purchase.text);
    final saleMinor = parseMoneyMinor(sale.text);
    final lowQuantity = parseQuantity(low.text);
    if (purchaseMinor == null || saleMinor == null || lowQuantity == null) {
      setState(() => error = 'Enter valid non-negative values.');
      return;
    }
    if (_identityProblem() case final problem?) {
      setState(() => error = problem);
      return;
    }
    final newName = name.text.trim();
    final code = barcode.text.trim().isEmpty ? null : barcode.text.trim();
    final label = pack.text.trim().isEmpty ? null : pack.text.trim();
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
          name: _sharedLocked || newName == product.editableName
              ? null
              : newName,
          categoryId:
              _sharedLocked ||
                  categoryId == null ||
                  categoryId == product.categoryId
              ? null
              : categoryId,
          barcode: code,
          barcodeChanged: code != product.barcode,
          unit: unit == storedUnit ? null : unit,
          packLabel: label,
          packLabelChanged: measure == null && label != product.packLabel,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is ProductValidationException
              ? e.message
              : safeUserMessage(e, fallback: 'Could not update product.');
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _adjustStock() async {
    final adjust = widget.onAdjustStock;
    if (adjust == null || saving || busy) return;
    setState(() => busy = true);
    try {
      final updated = await adjust();
      if (updated != null && mounted) setState(() => stock = updated);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    final delete = widget.onDelete;
    if (delete == null || saving || busy) return;
    setState(() => busy = true);
    final archived = await delete();
    if (!mounted) return;
    if (archived) {
      Navigator.pop(context, true);
    } else {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    title: context.l10n.editTitle,
    subtitle: productDisplayName(context, product.name, productId: product.id),
    maxWidth: 760,
    locked: saving || busy,
    message: error == null
        ? null
        : Text(
            localizedMessage(context.l10n, error!),
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
      final fields = _fields(context);
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
      if (widget.onDelete != null)
        TextButton.icon(
          key: const ValueKey('edit-product-archive'),
          onPressed: saving || busy ? null : _delete,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.archive_outlined),
          label: Text(context.l10n.editArchive),
        ),
      TextButton(
        onPressed: saving || busy ? null : () => Navigator.pop(context),
        child: Text(context.l10n.commonCancel),
      ),
      FilledButton(
        key: const ValueKey('edit-product-save'),
        onPressed: processingImage || saving || busy ? null : _submit,
        child: Text(
          saving ? context.l10n.commonSaving : context.l10n.commonSave,
        ),
      ),
    ],
  );

  Widget _fields(BuildContext context) {
    final l10n = context.l10n;
    final unitLabel = measure == null
        ? null
        : localizedWholeUnit(l10n, measure!);
    final barcodeField = TextField(
      key: const ValueKey('edit-product-barcode'),
      controller: barcode,
      textDirection: TextDirection.ltr,
      inputFormatters: const [AsciiDigitsFormatter()],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: l10n.fieldBarcode,
        hintText: l10n.commonOptional,
      ),
    );
    final unitField = _unitEditable
        ? DropdownButtonFormField<ProductUnit>(
            key: const ValueKey('edit-product-unit'),
            initialValue: unit,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.customUnitRequired),
            items: _countUnits
                .map(
                  (u) => DropdownMenuItem(
                    value: u,
                    child: Text(l10n.unitName(u.name, u.label)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => unit = v),
          )
        : InputDecorator(
            key: const ValueKey('edit-product-unit-fixed'),
            decoration: InputDecoration(
              labelText: l10n.customUnitRequired,
              helperText: measure == null && !_variant
                  ? l10n.editUnitLocked
                  : null,
              helperMaxLines: 2,
            ),
            child: Text(
              measure == null
                  ? l10n.unitName(
                      product.unit,
                      humanizeIdentifier(product.unit),
                    )
                  : measure == MeasureUnit.kg
                  ? l10n.editLooseWeight
                  : l10n.editLooseVolume,
              key: measure == null
                  ? null
                  : const ValueKey('edit-product-measure'),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSectionLabel(l10n.customProductDetails),
        TextField(
          key: const ValueKey('edit-product-name'),
          controller: name,
          readOnly: _sharedLocked,
          enabled: !_sharedLocked,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.customProductName,
            helperText: _variant ? l10n.editFamilyShared : null,
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        FieldPair(
          widget.categories.isEmpty || _sharedLocked
              ? InputDecorator(
                  key: const ValueKey('edit-product-category-fixed'),
                  decoration: InputDecoration(
                    labelText: l10n.productsCategoryLabel,
                  ),
                  child: Text(
                    categoryLabel(
                      context,
                      id: product.categoryId,
                      name: product.categoryName,
                    ),
                  ),
                )
              : DropdownButtonFormField<String>(
                  key: const ValueKey('edit-product-category'),
                  initialValue: categoryId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.customCategoryRequired,
                  ),
                  items: widget.categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            categoryLabel(context, id: c.id, name: c.name),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => categoryId = v),
                ),
          unitField,
        ),
        const SizedBox(height: 12),
        if (measure != null)
          barcodeField
        else
          FieldPair(
            barcodeField,
            TextField(
              key: const ValueKey('edit-product-pack'),
              controller: pack,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: _variant
                    ? '${l10n.customPackLabel} *'
                    : l10n.customPackLabel,
                hintText: l10n.customPackLabelHint,
              ),
            ),
          ),
        const SizedBox(height: 24),
        FormSectionLabel(l10n.customPricingStock),
        FieldPair(
          moneyField(
            purchase,
            unitLabel == null
                ? l10n.fieldPurchasePrice
                : l10n.fieldPurchasePricePer(unitLabel),
            key: const ValueKey('edit-product-purchase'),
          ),
          moneyField(
            sale,
            unitLabel == null
                ? l10n.fieldSalePrice
                : l10n.fieldSalePricePer(unitLabel),
            key: const ValueKey('edit-product-sale'),
          ),
        ),
        const SizedBox(height: 12),
        quantityField(
          low,
          unitLabel == null
              ? l10n.fieldLowStockAlert
              : l10n.fieldLowStockAlertIn(unitLabel),
          key: const ValueKey('edit-product-low'),
          onSubmitted: measure == null ? _submit : null,
        ),
        const SizedBox(height: 24),
        FormSectionLabel(l10n.editStockSection),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.posStock(
                bidiQuantity(
                  context,
                  localizedLineQuantity(l10n, stock, measure),
                ),
              ),
              key: const ValueKey('edit-product-stock'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (widget.onAdjustStock != null)
              OutlinedButton.icon(
                key: const ValueKey('edit-product-adjust-stock'),
                onPressed: saving || busy ? null : _adjustStock,
                icon: const Icon(Icons.inventory_outlined),
                label: Text(l10n.editAdjustStock),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(l10n.editStockHint, style: Theme.of(context).textTheme.bodySmall),
        if (measure case final unit?) ...[
          const SizedBox(height: 16),
          FormSectionLabel(l10n.customQuickQuantities),
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
            title: Text(l10n.customAllowCustom),
          ),
        ],
        const SizedBox(height: 16),
        FormSectionLabel(l10n.editAvailability),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: active,
          onChanged: (value) => setState(() => active = value),
          title: Text(l10n.editActive),
          subtitle: Text(l10n.editActiveHint),
        ),
      ],
    );
  }
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
      title: Text(context.l10n.dupTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.dupAlreadyHas),
            const SizedBox(height: 8),
            for (final match in matches.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${productDisplayName(context, match.name)}'
                  '${match.sameBarcode ? '  ${context.l10n.dupSameBarcode}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (matches.length > 5)
              Text(context.l10n.dupMore('${matches.length - 5}')),
            const SizedBox(height: 12),
            Text(context.l10n.dupExplain),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.l10n.dupGoBack),
        ),
        FilledButton(
          key: const ValueKey('duplicate-create-anyway'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(context.l10n.dupCreateAnyway),
        ),
      ],
    ),
  );
  return result == true;
}

/// Asks the owner before deleting [product], showing where it is used on
/// this device. A product is never removed: it is archived (hidden from new
/// sales; old bills, stock history and reports keep it) and can be restored.
/// Returns true once [archive] has succeeded.
Future<bool> confirmArchiveProduct(
  BuildContext context, {
  required ManagedProduct product,
  required Future<ProductUsage> usage,
  required Future<void> Function() archive,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ArchiveProductDialog(
        product: product,
        usage: usage,
        archive: archive,
      ),
    ) ==
    true;

class ArchiveProductDialog extends StatefulWidget {
  const ArchiveProductDialog({
    super.key,
    required this.product,
    required this.usage,
    required this.archive,
  });
  final ManagedProduct product;
  final Future<ProductUsage> usage;
  final Future<void> Function() archive;
  @override
  State<ArchiveProductDialog> createState() => _ArchiveProductDialogState();
}

class _ArchiveProductDialogState extends State<ArchiveProductDialog> {
  bool working = false, failed = false;

  Future<void> _archive() async {
    if (working) return;
    setState(() {
      working = true;
      failed = false;
    });
    try {
      await widget.archive();
    } catch (_) {
      if (mounted) {
        setState(() {
          working = false;
          failed = true;
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
      canPop: !working,
      child: AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.archive_outlined),
        title: Text(
          l10n.archiveTitle(
            productDisplayName(
              context,
              widget.product.name,
              productId: widget.product.id,
            ),
          ),
        ),
        content: SizedBox(
          width: 460,
          child: FutureBuilder<ProductUsage>(
            future: widget.usage,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Text(l10n.archiveChecking);
              }
              final usage = snapshot.data;
              // If the history cannot be read, treat it as used: archiving
              // is always safe.
              final hasHistory = usage?.hasHistory ?? true;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (usage != null && usage.hasHistory) ...[
                    Text(
                      l10n.archiveHistoryCounts(
                        '${usage.saleLines}',
                        '${usage.purchaseLines}',
                        '${usage.returnLines}',
                        '${usage.movements}',
                      ),
                      key: const ValueKey('archive-usage'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    hasHistory
                        ? l10n.archiveHistoryExplain
                        : l10n.archiveUnusedExplain,
                  ),
                  if (failed) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.archiveFailed,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: working ? null : () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FutureBuilder<ProductUsage>(
            future: widget.usage,
            builder: (context, snapshot) => FilledButton(
              key: const ValueKey('archive-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed:
                  working || snapshot.connectionState != ConnectionState.done
                  ? null
                  : _archive,
              child: Text(working ? l10n.archiveWorking : l10n.archiveConfirm),
            ),
          ),
        ],
      ),
    );
  }
}
