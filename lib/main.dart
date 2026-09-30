import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/dukaan_pro_app.dart';
import 'core/config/app_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.validate();
  if (AppEnvironment.hasSupabaseConfiguration) {
    await Supabase.initialize(
      url: AppEnvironment.supabaseUrl,
      publishableKey: AppEnvironment.supabaseAnonKey,
    );
  }
  runApp(
    DukaanProApp(
      supabase: AppEnvironment.hasSupabaseConfiguration
          ? Supabase.instance.client
          : null,
    ),
  );
}
