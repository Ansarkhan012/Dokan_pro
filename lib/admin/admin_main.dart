// Private Dokan Pro platform administration panel.
//
//   flutter run -d windows -t lib/admin/admin_main.dart \
//     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
//
// Uses only the public anon key and the administrator's own login. The
// session is kept in memory, so every launch asks for the password again.
// Authority comes from dukaan_private.platform_admins on the server.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_environment.dart';
import 'admin_app.dart';
import 'admin_gateway.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppEnvironment.hasSupabaseConfiguration) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Set SUPABASE_URL and SUPABASE_ANON_KEY (--dart-define).',
            ),
          ),
        ),
      ),
    );
    return;
  }
  final client = SupabaseClient(
    AppEnvironment.supabaseUrl,
    AppEnvironment.supabaseAnonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: true),
  );
  runApp(AdminApp(gateway: SupabaseAdminGateway(client)));
}
