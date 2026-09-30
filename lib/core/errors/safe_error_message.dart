import 'package:supabase_flutter/supabase_flutter.dart';

String safeUserMessage(Object error, {required String fallback}) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login') ||
        message.contains('invalid credentials')) {
      return 'Wrong email or password.';
    }
    if (message.contains('expired') || message.contains('refresh token')) {
      return 'Your session expired. Please sign in again.';
    }
  }
  return fallback;
}
