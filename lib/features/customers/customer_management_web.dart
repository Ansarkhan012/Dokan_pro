import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/l10n/l10n.dart';

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
    appBar: AppBar(title: Text(context.l10n.customersTitle)),
    body: Center(child: Text(context.l10n.customersWebOnly)),
  );
}
