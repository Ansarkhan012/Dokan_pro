import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExpenseManagementScreen extends StatelessWidget {
  const ExpenseManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expenses')),
    body: const Center(
      child: Text(
        'Offline expense management is available on Android and Windows.',
      ),
    ),
  );
}
