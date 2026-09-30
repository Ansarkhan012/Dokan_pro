import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/cashier_session_manager.dart';
import '../auth/cashier_session_store.dart';
import '../auth/cashier_session.dart';
import '../auth/supabase_cashier_auth_gateway.dart';
import '../features/shop/cashier_admin_gateway.dart';
import '../features/shop/supabase_cashier_admin_gateway.dart';
import 'owner_cashier_setup_panel.dart';

class CashierLoginPanel extends StatefulWidget {
  const CashierLoginPanel({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
    required this.deviceIdentifier,
    required this.onAuthenticated,
  });

  final SupabaseClient client;
  final String shopId;
  final String shopName;
  final String deviceIdentifier;
  final void Function(CashierSession session, String cashierName)
  onAuthenticated;

  @override
  State<CashierLoginPanel> createState() => _CashierLoginPanelState();
}

class _CashierLoginPanelState extends State<CashierLoginPanel> {
  late final manager = CashierSessionManager(
    SupabaseCashierAuthGateway(widget.client),
    SecureCashierSessionStore(),
  );
  late final CashierAdminGateway admin = SupabaseCashierAdminGateway(
    widget.client,
  );
  late Future<List<CashierMetadata>> cashiers = _load();
  final pin = TextEditingController();
  String? selected;
  String? message;
  bool showManagement = false;
  bool isLoggingIn = false;

  Future<List<CashierMetadata>> _load() =>
      admin.cashiers(shopId: widget.shopId);

  Future<void> _refresh() async {
    final refreshed = _load();
    setState(() {
      cashiers = refreshed;
      message = null;
    });
    final rows = await refreshed;
    if (!mounted) return;
    if (!rows.any((cashier) => cashier.isActive && cashier.id == selected)) {
      setState(() => selected = null);
    }
  }

  Future<void> login() async {
    if (selected == null || isLoggingIn) return;
    final rawPin = pin.text;
    pin.clear();
    if (!RegExp(r'^\d{4,8}$').hasMatch(rawPin)) {
      setState(() => message = 'Enter the cashier’s 4 to 8 digit PIN.');
      return;
    }
    setState(() {
      isLoggingIn = true;
      message = null;
    });
    try {
      final session = await manager.login(
        shopId: widget.shopId,
        deviceIdentifier: widget.deviceIdentifier,
        cashierId: selected!,
        pin: rawPin,
      );
      if (!mounted) return;
      final cashierName = (await cashiers)
          .firstWhere((cashier) => cashier.id == selected)
          .displayName;
      if (!mounted) return;
      setState(() {
        isLoggingIn = false;
        message =
            'Cashier authenticated. Offline billing remains available until local expiry.';
      });
      widget.onAuthenticated(session, cashierName);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoggingIn = false;
        message = 'Login failed or temporarily locked.';
      });
    }
  }

  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CashierMetadata>>(
    future: cashiers,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Could not load cashiers. Please try again.'),
            OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
          ],
        );
      }

      final allCashiers = snapshot.data ?? const <CashierMetadata>[];
      final activeCashiers = allCashiers
          .where((cashier) => cashier.isActive)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dukaan Pro — ${widget.shopName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (activeCashiers.isEmpty) ...[
            Text(
              allCashiers.isEmpty
                  ? 'No cashier has been created yet.'
                  : 'No active cashier is available.',
            ),
            FilledButton.icon(
              onPressed: () => setState(() => showManagement = true),
              icon: Icon(
                allCashiers.isEmpty ? Icons.person_add : Icons.manage_accounts,
              ),
              label: Text(
                allCashiers.isEmpty
                    ? 'Create first cashier'
                    : 'Manage cashiers',
              ),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Select cashier'),
              items: activeCashiers
                  .map(
                    (cashier) => DropdownMenuItem(
                      value: cashier.id,
                      child: Text(cashier.displayName),
                    ),
                  )
                  .toList(),
              onChanged: isLoggingIn
                  ? null
                  : (value) => setState(() => selected = value),
            ),
            TextField(
              controller: pin,
              enabled: !isLoggingIn,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            FilledButton(
              onPressed: selected == null || isLoggingIn ? null : login,
              child: Text(isLoggingIn ? 'Signing in…' : 'Start Shift / Login'),
            ),
          ],
          TextButton(
            onPressed: () => setState(() => showManagement = !showManagement),
            child: Text(
              showManagement ? 'Hide cashier setup' : 'Manage cashiers',
            ),
          ),
          if (showManagement)
            OwnerCashierSetupPanel(
              gateway: admin,
              shopId: widget.shopId,
              cashiers: allCashiers,
              onChanged: _refresh,
              startWithCreateForm: allCashiers.isEmpty,
            ),
          if (message != null) Text(message!),
        ],
      );
    },
  );
}
