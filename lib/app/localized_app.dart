import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/locale_controller.dart';

/// The app's `MaterialApp` with its language wiring: English (default) and
/// Urdu (RTL), Material/Cupertino/Widgets localizations, and the theme for
/// the current language.
///
/// A language switch rebuilds only this configuration. `MaterialApp` keeps
/// its navigator, so [home], pushed routes, the signed-in session and the
/// cart below keep their state.
class LocalizedMaterialApp extends StatelessWidget {
  const LocalizedMaterialApp({
    super.key,
    required this.controller,
    required this.home,
  });

  final LocaleController controller;
  final Widget home;

  @override
  Widget build(BuildContext context) => LocaleScope(
    controller: controller,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp(
        title: 'Dukaan Pro',
        debugShowCheckedModeBanner: false,
        theme: appTheme(controller),
        locale: controller.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      ),
    ),
  );
}
