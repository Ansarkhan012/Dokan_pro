import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CashierResumeGate extends StatelessWidget {
  const CashierResumeGate({
    super.key,
    required this.client,
    required this.child,
  });

  final SupabaseClient client;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
