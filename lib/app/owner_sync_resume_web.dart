import 'package:supabase_flutter/supabase_flutter.dart';

/// The web preview has no local queue.
Future<void> resumeOwnerSync({
  required SupabaseClient ownerClient,
  required String shopId,
  required String deviceId,
}) async {}
