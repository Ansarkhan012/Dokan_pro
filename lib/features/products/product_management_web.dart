import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/l10n/l10n.dart';

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
    appBar: AppBar(title: Text(context.l10n.productsTitle)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(context.l10n.productsWebOnly, textAlign: TextAlign.center),
      ),
    ),
  );
}
