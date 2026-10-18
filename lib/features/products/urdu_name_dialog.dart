import 'package:flutter/material.dart';

import '../../core/l10n/bidi.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/product_names.dart';

/// Lets the owner set or remove a product's Urdu display name. Saved on this
/// device only; the English product name and all shop data are unchanged.
Future<void> showUrduNameDialog(
  BuildContext context, {
  required String productId,
  required String englishName,
}) async {
  final resolver = ProductNamesScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _UrduNameDialog(
      resolver: resolver,
      productId: productId,
      englishName: englishName,
    ),
  );
  if (saved == true) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.productUrduNameSaved)));
  }
}

class _UrduNameDialog extends StatefulWidget {
  const _UrduNameDialog({
    required this.resolver,
    required this.productId,
    required this.englishName,
  });
  final ProductDisplayNameResolver resolver;
  final String productId;
  final String englishName;
  @override
  State<_UrduNameDialog> createState() => _UrduNameDialogState();
}

class _UrduNameDialogState extends State<_UrduNameDialog> {
  late final controller = TextEditingController(
    text:
        widget.resolver.manualUrdu(widget.productId) ??
        _suggestion(widget.resolver, widget.productId, widget.englishName),
  );

  static String _suggestion(
    ProductDisplayNameResolver resolver,
    String productId,
    String englishName,
  ) {
    final source = resolver.sourceOf(
      englishName,
      productId: productId,
      languageCode: 'ur',
    );
    return source == ProductNameSource.original
        ? ''
        : resolver.resolve(
            englishName,
            productId: productId,
            languageCode: 'ur',
          );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save(String urdu) async {
    await widget.resolver.setManualUrdu(
      productId: widget.productId,
      englishName: widget.englishName,
      urdu: urdu,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasManual = widget.resolver.manualUrdu(widget.productId) != null;
    return AlertDialog(
      title: Text(
        l10n.productUrduNameTitle(bidiName(context, widget.englishName)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('urdu-name-field'),
            controller: controller,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(labelText: l10n.productUrduNameAction),
          ),
          const SizedBox(height: 8),
          Text(l10n.productUrduNameHint),
          if (!widget.resolver.automaticTranslationAvailable) ...[
            const SizedBox(height: 4),
            Text(
              l10n.productUrduNameAutoOff,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        if (hasManual)
          TextButton(
            onPressed: () => _save(''),
            child: Text(l10n.productUrduNameRemove),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('urdu-name-save'),
          onPressed: () => _save(controller.text),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
