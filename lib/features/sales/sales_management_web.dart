import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/l10n/l10n.dart';

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
    appBar: AppBar(title: Text(context.l10n.salesWebTitle)),
    body: Center(child: Text(context.l10n.salesWebOnly)),
  );
}
