import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/dukaan_pro_app.dart';
import 'auth/secure_owner_session_storage.dart';
import 'core/config/app_environment.dart';
import 'core/images/product_image_bootstrap.dart';
import 'core/l10n/l10n.dart';
import 'core/l10n/offline_urdu_translation.dart';
import 'core/l10n/product_display_names.dart';
import 'core/l10n/locale_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.validate();
  await initializeProductImages();
  registerFontLicenses();
  // Read before runApp so a chosen Urdu UI never flashes English first.
  final localeController = await LocaleController.load(
    const SharedPreferencesLocaleStore(),
  );
  // Urdu product names saved on this device, translated offline by ML Kit
  // once the owner downloads the models in Settings. Startup only checks
  // whether the models exist; it never downloads them.
  final urduTranslation = OfflineUrduTranslation();
  unawaited(urduTranslation.checkModels());
  ProductDisplayNameResolver.instance = await ProductDisplayNameResolver.load(
    const SharedPreferencesProductTranslationStore(),
    service: urduTranslation,
  );
  LocalStorage? ownerSessionStorage;
  if (AppEnvironment.hasSupabaseConfiguration) {
    // The owner's session lives in secure storage on devices; the web preview
    // keeps supabase_flutter's default.
    final storage = kIsWeb
        ? SharedPreferencesLocalStorage(
            persistSessionKey: supabaseSessionKey(AppEnvironment.supabaseUrl),
          )
        : SecureOwnerSessionStorage(
            persistSessionKey: supabaseSessionKey(AppEnvironment.supabaseUrl),
          );
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(localStorage: storage),
    );
    ownerSessionStorage = storage;
  }
  runApp(
    DukaanProApp(
      supabase: AppEnvironment.hasSupabaseConfiguration
          ? Supabase.instance.client
          : null,
      ownerSessionStorage: ownerSessionStorage,
      localeController: localeController,
    ),
  );
}
