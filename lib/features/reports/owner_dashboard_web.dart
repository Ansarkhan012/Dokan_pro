import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/bidi.dart';
import '../../core/l10n/l10n.dart';

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
    appBar: AppBar(
      title: Text(context.l10n.dashboardWebTitle(bidiName(context, shopName))),
    ),
    body: Center(
      child: Text(context.l10n.dashboardWebOnly, textAlign: TextAlign.center),
    ),
  );
}
