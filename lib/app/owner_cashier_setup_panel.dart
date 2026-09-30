import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/shop/cashier_admin_gateway.dart';

class OwnerCashierSetupPanel extends StatefulWidget {
  const OwnerCashierSetupPanel({
    super.key,
    required this.gateway,
    required this.shopId,
    required this.cashiers,
    required this.onChanged,
    this.startWithCreateForm = false,
  });

  final CashierAdminGateway gateway;
  final String shopId;
  final List<CashierMetadata> cashiers;
  final Future<void> Function() onChanged;
  final bool startWithCreateForm;

  @override
  State<OwnerCashierSetupPanel> createState() => _OwnerCashierSetupPanelState();
}

class _OwnerCashierSetupPanelState extends State<OwnerCashierSetupPanel> {
  final name = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  final updating = <String>{};
  late bool showCreateForm = widget.startWithCreateForm;
  bool isCreating = false;
  String? error;

  Future<void> create() async {
    if (isCreating) return;
    final displayName = name.text.trim();
    final rawPin = pin.text;
    if (displayName.isEmpty) {
      setState(() => error = 'Enter the cashier name.');
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(rawPin)) {
      setState(() => error = 'PIN must contain 4 to 8 digits.');
      return;
    }
    if (rawPin != confirmPin.text) {
      setState(() => error = 'PINs do not match.');
      return;
    }

    setState(() {
      isCreating = true;
      error = null;
    });
    pin.clear();
    confirmPin.clear();
    try {
      await widget.gateway.createCashier(
        shopId: widget.shopId,
        displayName: displayName,
        pin: rawPin,
      );
      name.clear();
      await widget.onChanged();
      if (!mounted) return;
      setState(() {
        isCreating = false;
        showCreateForm = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isCreating = false;
        error = 'Could not create the cashier. Please try again.';
      });
    }
  }

  Future<void> setActive(CashierMetadata cashier, bool isActive) async {
    if (updating.contains(cashier.id)) return;
    setState(() {
      updating.add(cashier.id);
      error = null;
    });
    try {
      await widget.gateway.setActive(
        shopId: widget.shopId,
        cashierId: cashier.id,
        isActive: isActive,
      );
      await widget.onChanged();
      if (!mounted) return;
      setState(() => updating.remove(cashier.id));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        updating.remove(cashier.id);
        error = 'Could not update the cashier. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    pin.dispose();
    confirmPin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Cashiers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            onPressed: isCreating
                ? null
                : () => setState(() => showCreateForm = !showCreateForm),
            icon: const Icon(Icons.person_add),
            label: const Text('Create cashier'),
          ),
        ],
      ),
      for (final cashier in widget.cashiers)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(cashier.displayName),
          subtitle: Text(cashier.isActive ? 'Active' : 'Disabled'),
          value: cashier.isActive,
          onChanged: updating.contains(cashier.id)
              ? null
              : (value) => setActive(cashier, value),
        ),
      if (showCreateForm) ...[
        TextField(
          controller: name,
          enabled: !isCreating,
          decoration: const InputDecoration(labelText: 'Cashier name'),
        ),
        TextField(
          controller: pin,
          enabled: !isCreating,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Numeric PIN'),
        ),
        TextField(
          controller: confirmPin,
          enabled: !isCreating,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Confirm PIN'),
        ),
        FilledButton(
          onPressed: isCreating ? null : create,
          child: Text(isCreating ? 'Creating…' : 'Create cashier'),
        ),
      ],
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
