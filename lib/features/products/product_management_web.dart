import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductManagementScreen extends StatelessWidget {
  const ProductManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId;
  final String deviceId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Products')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Product management uses the native Drift catalog. Open Dukaan Pro on Windows or Android.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
