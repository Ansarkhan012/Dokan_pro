import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';

class DukaanProApp extends StatelessWidget {
  const DukaanProApp({super.key, this.supabase, this.ownerSessionStorage});
  final SupabaseClient? supabase;

  /// Where the owner's session is persisted, so cashier mode can verify that
  /// no owner token remains on the device.
  final LocalStorage? ownerSessionStorage;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dukaan Pro',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xff176b52)),
    home: supabase == null
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
            client: supabase!,
            ownerSessionStorage: ownerSessionStorage ?? const EmptyLocalStorage(),
          ),
  );
}
