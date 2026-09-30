import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerDashboardScreen extends StatelessWidget {
  const OwnerDashboardScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
  });
  final SupabaseClient client;
  final String shopId, shopName;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('$shopName Dashboard')),
    body: const Center(
      child: Text(
        'Offline owner reports are available on Android and Windows.',
      ),
    ),
  );
}
