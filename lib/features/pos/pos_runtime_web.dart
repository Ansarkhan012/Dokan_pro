import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PosRuntime extends StatelessWidget {
  const PosRuntime({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
    required this.cashierId,
    required this.cashierName,
    required this.deviceId,
    required this.onExit,
  });

  final SupabaseClient client;
  final String shopId;
  final String shopName;
  final String cashierId;
  final String cashierName;
  final String deviceId;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('$shopName • POS preview')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.desktop_windows_outlined,
                  size: 56,
                  color: Color(0xff176b52),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cashier authentication successful',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('$cashierName is signed in.'),
                const SizedBox(height: 12),
                const Text(
                  'The offline POS database is available on Android and Windows. Chrome remains an auth and onboarding preview target.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: onExit,
                  child: const Text('End preview session'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
