import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The web preview has no cashier runtime, so no device mode either.
class CashierResumeGate extends StatelessWidget {
  const CashierResumeGate({
    super.key,
    required this.client,
    required this.ownerSessionStorage,
    required this.reloadSignal,
    required this.child,
  });

  final SupabaseClient client;
  final LocalStorage ownerSessionStorage;
  final Listenable reloadSignal;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
