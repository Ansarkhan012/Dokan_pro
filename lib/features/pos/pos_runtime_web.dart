import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';

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
    appBar: AppBar(
      title: Text(context.l10n.posPreviewTitle(bidiName(context, shopName))),
    ),
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
                  context.l10n.posPreviewAuthenticated,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.posPreviewSignedIn(
                    bidiName(context, cashierName),
                  ),
                ),
                const SizedBox(height: 12),
                Text(context.l10n.posPreviewNote, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: onExit,
                  child: Text(context.l10n.posPreviewEnd),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
