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
import '../core/l10n/digits.dart';
import '../core/l10n/bidi.dart';
import '../core/l10n/l10n.dart';

class CashierLoginPanel extends StatefulWidget {
  const CashierLoginPanel({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
    required this.deviceIdentifier,
    required this.onAuthenticated,
    this.allowManagement = false,
    this.directory,
  });

  final SupabaseClient client;
  final String shopId;
  final String shopName;
  final String deviceIdentifier;
  final void Function(CashierSession session, String cashierName)
  onAuthenticated;

  /// Cashier setup needs a verified owner; never shown from the device lobby
  /// or while owner mode is locked.
  final bool allowManagement;

  /// Where the cashier list comes from; defaults to the owner's view.
  final CashierAdminGateway? directory;

  @override
  State<CashierLoginPanel> createState() => _CashierLoginPanelState();
}

class _CashierLoginPanelState extends State<CashierLoginPanel> {
  late final manager = CashierSessionManager(
    SupabaseCashierAuthGateway(widget.client),
    SecureCashierSessionStore(),
  );
  late final CashierAdminGateway admin =
      widget.directory ?? SupabaseCashierAdminGateway(widget.client);
  late Future<List<CashierMetadata>> cashiers = _load();
  final pin = TextEditingController();
  String? selected;

  /// Resolved when shown, so a language switch also translates it.
  String Function(AppLocalizations)? message;
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
      setState(() => message = (l10n) => l10n.cashierErrPinFormat);
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
        message = (l10n) => l10n.cashierAuthenticated;
      });
      widget.onAuthenticated(session, cashierName);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoggingIn = false;
        message = (l10n) => l10n.cashierLoginFailed;
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
            Text(context.l10n.cashierLoadFailed),
            OutlinedButton(
              onPressed: _refresh,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        );
      }

      final l10n = context.l10n;
      final allCashiers = snapshot.data ?? const <CashierMetadata>[];
      final activeCashiers = allCashiers
          .where((cashier) => cashier.isActive)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cashierLoginHeading(bidiName(context, widget.shopName)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (activeCashiers.isEmpty) ...[
            Text(
              allCashiers.isEmpty
                  ? l10n.cashierNoneCreated
                  : l10n.cashierNoneActive,
            ),
            if (!widget.allowManagement) Text(l10n.cashierAskOwner),
            if (widget.allowManagement)
              FilledButton.icon(
                onPressed: () => setState(() => showManagement = true),
                icon: Icon(
                  allCashiers.isEmpty
                      ? Icons.person_add
                      : Icons.manage_accounts,
                ),
                label: Text(
                  allCashiers.isEmpty
                      ? l10n.cashierCreateFirst
                      : l10n.cashierManage,
                ),
              ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: InputDecoration(labelText: l10n.cashierSelect),
              items: activeCashiers
                  .map(
                    (cashier) => DropdownMenuItem(
                      value: cashier.id,
                      child: Text(bidiName(context, cashier.displayName)),
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
              inputFormatters: [
                const AsciiDigitsFormatter(),
                FilteringTextInputFormatter.digitsOnly,
              ],
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l10n.cashierPin),
            ),
            FilledButton(
              onPressed: selected == null || isLoggingIn ? null : login,
              child: Text(
                isLoggingIn ? l10n.cashierSigningIn : l10n.cashierStartShift,
              ),
            ),
          ],
          if (widget.allowManagement)
            TextButton(
              onPressed: () => setState(() => showManagement = !showManagement),
              child: Text(
                showManagement ? l10n.cashierHideSetup : l10n.cashierManage,
              ),
            ),
          if (widget.allowManagement && showManagement)
            OwnerCashierSetupPanel(
              gateway: admin,
              shopId: widget.shopId,
              cashiers: allCashiers,
              onChanged: _refresh,
              startWithCreateForm: allCashiers.isEmpty,
            ),
          if (message case final message?) Text(message(l10n)),
        ],
      );
    },
  );
}
