import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/l10n/locale_controller.dart';
import 'auth_gate.dart';
import '../features/app_update/app_update_host.dart';
import '../features/app_update/update_controller.dart';
import '../core/l10n/product_names.dart';
import 'localized_app.dart';

class DukaanProApp extends StatefulWidget {
  const DukaanProApp({
    super.key,
    this.supabase,
    this.ownerSessionStorage,
    this.localeController,
    this.updateController,
  });
  final SupabaseClient? supabase;

  /// Where the owner's session is persisted, so cashier mode can verify that
  /// no owner token remains on the device.
  final LocalStorage? ownerSessionStorage;

  /// The UI language, loaded before `runApp`. Defaults to English in memory.
  final LocaleController? localeController;

  /// In-app APK updates; defaults to the build's configuration (null, and
  /// so off, unless the APP_UPDATE_* defines are set and on Android).
  final UpdateController? updateController;

  @override
  State<DukaanProApp> createState() => _DukaanProAppState();
}

class _DukaanProAppState extends State<DukaanProApp> {
  late final LocaleController locale =
      widget.localeController ?? LocaleController();
  late final UpdateController? updates =
      widget.updateController ?? UpdateController.fromEnvironment();

  @override
  Widget build(BuildContext context) => ProductNamesScope(
    resolver: ProductDisplayNameResolver.instance,
    child: LocalizedMaterialApp(
      controller: locale,
      home: AppUpdateHost(
        controller: updates,
        child: widget.supabase == null
            ? const Scaffold(
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Dukaan Pro is not connected. Provide SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define.',
                    ),
                  ),
                ),
              )
            : AuthGate(
                client: widget.supabase!,
                ownerSessionStorage:
                    widget.ownerSessionStorage ?? const EmptyLocalStorage(),
              ),
      ),
    ),
  );
}
