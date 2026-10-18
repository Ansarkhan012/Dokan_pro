import 'package:flutter/widgets.dart';

import 'bidi.dart';
import 'l10n.dart';
import 'product_display_names.dart';

export 'product_display_names.dart';

/// Provides the app's [ProductDisplayNameResolver]; product names rebuild
/// when a translation or correction arrives. Without a scope widgets use
/// [ProductDisplayNameResolver.instance].
class ProductNamesScope extends InheritedNotifier<ProductDisplayNameResolver> {
  const ProductNamesScope({
    super.key,
    required ProductDisplayNameResolver resolver,
    required super.child,
  }) : super(notifier: resolver);

  static ProductDisplayNameResolver of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ProductNamesScope>()
          ?.notifier ??
      ProductDisplayNameResolver.instance;
}

/// Whether the current UI language is Urdu.
bool isUrduUi(BuildContext context) => context.l10n.localeName.startsWith('ur');

/// A product name ready for a widget: the resolver's name for the current
/// language (English unchanged) and direction-isolated like [bidiName].
/// With a [productId], a missing Urdu name is queued for background
/// translation (once; a no-op while no translation engine is installed).
String productDisplayName(
  BuildContext context,
  String name, {
  String? productId,
}) {
  final resolver = ProductNamesScope.of(context);
  final languageCode = isUrduUi(context) ? 'ur' : 'en';
  if (productId != null &&
      languageCode == 'ur' &&
      resolver.automaticTranslationAvailable &&
      resolver.sourceOf(
            name,
            productId: productId,
            languageCode: languageCode,
          ) ==
          ProductNameSource.original) {
    resolver.requestTranslations([(productId: productId, name: name)]);
  }
  return bidiName(
    context,
    resolver.resolve(name, productId: productId, languageCode: languageCode),
  );
}
