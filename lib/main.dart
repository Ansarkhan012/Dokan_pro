import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/dukaan_pro_app.dart';
import 'auth/secure_owner_session_storage.dart';
import 'core/config/app_environment.dart';
import 'core/images/product_image_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.validate();
  await initializeProductImages();
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
    ),
  );
}
