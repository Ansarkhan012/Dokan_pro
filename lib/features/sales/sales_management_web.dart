import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalesManagementScreen extends StatelessWidget {
  const SalesManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, shopName, deviceId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales')),
    body: const Center(
      child: Text('Sales management is available on Windows and Android.'),
    ),
  );
}
