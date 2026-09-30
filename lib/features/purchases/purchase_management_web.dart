import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PurchaseManagementScreen extends StatelessWidget {
  const PurchaseManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Suppliers & Purchases')),
    body: const Center(
      child: Text('Purchasing is available on Android and Windows.'),
    ),
  );
}
