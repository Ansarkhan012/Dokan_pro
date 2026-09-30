import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerManagementScreen extends StatelessWidget {
  const CustomerManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customers / Khata')),
    body: const Center(
      child: Text(
        'Customer offline management is available on Android and Windows.',
      ),
    ),
  );
}
