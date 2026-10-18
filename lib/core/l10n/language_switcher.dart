import 'package:flutter/material.dart';

import 'l10n.dart';
import 'locale_controller.dart';

/// English / اردو menu. Switching never restarts the app, signs out, clears
/// the cart or leaves the current screen. While Urdu is active it also
/// offers the Nastaliq / Naskh font comparison.
///
/// Renders nothing outside the app shell (no [LocaleScope]), so screens
/// pumped on their own in tests are unchanged.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = LocaleScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    // Compact (40 px, like the POS logout button) so the narrowest POS top
    // bar (600 px) still fits.
    return SizedBox.square(
      dimension: 40,
      child: PopupMenuButton<Object>(
        key: const ValueKey('language-switcher'),
        tooltip: l10n.languageMenuTooltip,
        padding: EdgeInsets.zero,
        iconSize: 22,
        icon: const Icon(Icons.translate),
        onSelected: (value) => switch (value) {
          final Locale locale => controller.setLocale(locale),
          final UrduFont font => controller.setUrduFont(font),
          _ => null,
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem<Object>(
            key: const ValueKey('language-en'),
            value: LocaleController.english,
            checked: !controller.isUrdu,
            child: Text(l10n.languageEnglish),
          ),
          CheckedPopupMenuItem<Object>(
            key: const ValueKey('language-ur'),
            value: LocaleController.urdu,
            checked: controller.isUrdu,
            child: Text(l10n.languageUrdu),
          ),
          if (controller.isUrdu) ...[
            const PopupMenuDivider(),
            PopupMenuItem<Object>(
              enabled: false,
              height: 32,
              child: Text(l10n.urduFontHeading),
            ),
            for (final (font, label) in [
              (UrduFont.nastaliq, l10n.urduFontNastaliq),
              (UrduFont.naskh, l10n.urduFontNaskh),
            ])
              CheckedPopupMenuItem<Object>(
                key: ValueKey('urdu-font-${font.name}'),
                value: font,
                checked: controller.urduFont == font,
                child: Text(label),
              ),
          ],
        ],
      ),
    );
  }
}
