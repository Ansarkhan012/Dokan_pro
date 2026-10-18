import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'locale_controller.dart';

export '../../l10n/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  /// UI strings for the current locale. Only widgets use this; domain and
  /// service code never depend on the UI language.
  ///
  /// English when no app localizations are above this context (a widget
  /// pumped on its own in a test, or any bare `MaterialApp`), so a missing
  /// delegate can never crash a screen and English stays the default.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('en'));
}

/// The app theme. English is exactly the theme used before Stage 2. Urdu
/// only adds the bundled Urdu font as a fallback for Arabic-script glyphs:
/// Latin text and the Western digits keep the default font, so amounts look
/// the same in both languages. Material picks its taller Urdu typography
/// metrics itself from the locale.
ThemeData appTheme(LocaleController locale) {
  const seed = Color(0xff176b52);
  if (!locale.isUrdu) return ThemeData(colorSchemeSeed: seed);
  return ThemeData(
    colorSchemeSeed: seed,
    fontFamilyFallback: [locale.urduFont.family],
  );
}

/// Adds the bundled fonts' OFL licences to the app's licences page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, path) in const [
      ('Noto Nastaliq Urdu', 'assets/fonts/noto_nastaliq_urdu/OFL.txt'),
      ('Noto Naskh Arabic', 'assets/fonts/noto_naskh_arabic/OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        package,
      ], await rootBundle.loadString(path));
    }
  });
}
