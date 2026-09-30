final class AppEnvironment {
  const AppEnvironment._();
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  static bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static void validate() {
    if (appEnvironment == 'production' && !hasSupabaseConfiguration) {
      throw StateError(
        'Production requires SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define.',
      );
    }
  }
}
