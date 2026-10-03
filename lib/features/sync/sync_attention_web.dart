import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncAttentionScreen extends StatelessWidget {
  const SyncAttentionScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sync issues')),
    body: const Center(
      child: Text('Sync issues are available on Android and Windows.'),
    ),
  );
}
