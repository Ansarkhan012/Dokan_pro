import 'package:flutter/material.dart';
import '../../core/domain/enums.dart';
import '../pos/pos_state.dart';
import '../sales/domain/bill_reference.dart';
import 'customer_models.dart';

abstract interface class CustomerKhataActions {
  Future<List<CustomerAccount>> searchCustomers(String query);
  Future<List<CustomerLedgerLine>> statement(String customerId);
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  });
}

class CustomerKhataView extends StatefulWidget {
  const CustomerKhataView({super.key, required this.actions});
  final CustomerKhataActions actions;
  @override
  State<CustomerKhataView> createState() => _CustomerKhataViewState();
}

class _CustomerKhataViewState extends State<CustomerKhataView> {
  final search = TextEditingController();
  late Future<List<CustomerAccount>> customers = widget.actions.searchCustomers(
    '',
  );
  void refresh() =>
      setState(() => customers = widget.actions.searchCustomers(search.text));
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: search,
          onChanged: (_) => refresh(),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search customer name or phone',
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<CustomerAccount>>(
          future: customers,
          builder: (context, snap) {
            if (!snap.hasData) {
              return snap.hasError
                  ? Center(child: Text('Could not load Khata: ${snap.error}'))
                  : const Center(child: CircularProgressIndicator());
            }
            if (snap.data!.isEmpty) {
              return const Center(child: Text('No customers found.'));
            }
            return ListView.builder(
              itemCount: snap.data!.length,
              itemBuilder: (_, i) {
                final customer = snap.data![i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(customer.name.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(customer.name),
                  subtitle: Text(
                    '${customer.phone ?? 'No phone'}${customer.isActive ? '' : ' • Inactive'}',
                  ),
                  trailing: Text(
                    customer.balanceMinor == 0
                        ? 'Clear'
                        : '${formatPkr(customer.balanceMinor)} due',
                    style: TextStyle(
                      color: customer.balanceMinor > 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CustomerDetailPage(
                          customer: customer,
                          actions: widget.actions,
                        ),
                      ),
                    );
                    if (mounted) refresh();
                  },
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({
    super.key,
    required this.customer,
    required this.actions,
  });
  final CustomerAccount customer;
  final CustomerKhataActions actions;
  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late Future<List<CustomerLedgerLine>> lines = widget.actions.statement(
    widget.customer.id,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.customer.name)),
    floatingActionButton: widget.customer.isActive
        ? FloatingActionButton.extended(
            onPressed: receive,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Receive Payment'),
          )
        : null,
    body: FutureBuilder<List<CustomerLedgerLine>>(
      future: lines,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  children: [
                    _metric('Balance', formatPkr(widget.customer.balanceMinor)),
                    _metric(
                      'Credit limit',
                      widget.customer.creditLimitMinor == null
                          ? 'Not set'
                          : formatPkr(widget.customer.creditLimitMinor!),
                    ),
                    _metric(
                      'Credit sales',
                      formatPkr(widget.customer.totalCreditMinor),
                    ),
                    _metric(
                      'Payments',
                      formatPkr(widget.customer.totalPaymentsMinor),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Statement', style: Theme.of(context).textTheme.titleLarge),
            if (snap.data!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No ledger entries yet.')),
              ),
            for (final line in snap.data!)
              ListTile(
                leading: Icon(
                  line.signedAmountMinor >= 0
                      ? Icons.add_circle_outline
                      : Icons.remove_circle_outline,
                  color: line.signedAmountMinor >= 0
                      ? Colors.red
                      : Colors.green,
                ),
                title: Text(_ledgerLabel(line)),
                subtitle: Text(
                  '${_date(line.createdAt)}${line.note == null ? '' : ' • ${line.note}'}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${line.signedAmountMinor >= 0 ? '+' : '-'}${formatPkr(line.amountMinor.abs())}',
                    ),
                    Text(
                      'Balance ${formatPkr(line.runningBalanceMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 80),
          ],
        );
      },
    ),
  );
  Widget _metric(String label, String value) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
  Future<void> receive() async {
    final request = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) =>
          _ReceivePaymentDialog(maximumMinor: widget.customer.balanceMinor),
    );
    if (request == null) return;
    try {
      await widget.actions.receivePayment(
        customerId: widget.customer.id,
        amountMinor: request.amount,
        method: request.method,
        reference: request.reference,
        note: request.note,
      );
      if (!mounted) return;
      setState(() => lines = widget.actions.statement(widget.customer.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment saved locally and queued for sync.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment could not be recorded. Nothing was changed.',
            ),
          ),
        );
      }
    }
  }
}

class _ReceivePaymentDialog extends StatefulWidget {
  const _ReceivePaymentDialog({required this.maximumMinor});
  final int maximumMinor;
  @override
  State<_ReceivePaymentDialog> createState() => _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends State<_ReceivePaymentDialog> {
  final amount = TextEditingController(),
      reference = TextEditingController(),
      note = TextEditingController();
  PaymentMethod method = PaymentMethod.cash;
  String? error;
  bool submitting = false;
  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Receive Payment'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: 'Rs ',
            ),
          ),
          SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(value: PaymentMethod.cash, label: Text('Cash')),
              ButtonSegment(
                value: PaymentMethod.digital,
                label: Text('Digital'),
              ),
            ],
            selected: {method},
            onSelectionChanged: (v) => setState(() => method = v.single),
          ),
          TextField(
            controller: reference,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
            ),
          ),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: submitting
            ? null
            : () {
                final value = parseMoneyMinor(amount.text);
                if (value == null || value <= 0) {
                  setState(() => error = 'Enter an amount greater than zero.');
                  return;
                }
                if (value > widget.maximumMinor) {
                  setState(
                    () => error =
                        'Payment cannot exceed ${formatPkr(widget.maximumMinor)}.',
                  );
                  return;
                }
                setState(() => submitting = true);
                Navigator.pop(
                  context,
                  _PaymentInput(
                    value,
                    method,
                    _optional(reference.text),
                    _optional(note.text),
                  ),
                );
              },
        child: const Text('Record Payment'),
      ),
    ],
  );
}

final class _PaymentInput {
  const _PaymentInput(this.amount, this.method, this.reference, this.note);
  final int amount;
  final PaymentMethod method;
  final String? reference, note;
}

String? _optional(String v) => v.trim().isEmpty ? null : v.trim();
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _ledgerLabel(CustomerLedgerLine line) => switch (line.type) {
  CustomerLedgerType.creditSale =>
    'Sale${line.saleId == null ? '' : ' • ${billReference(line.saleId!)}'}',
  CustomerLedgerType.paymentReceived =>
    'Payment${line.paymentMethod == null ? '' : ' • ${line.paymentMethod}'}',
  CustomerLedgerType.openingBalance => 'Opening balance',
  CustomerLedgerType.refund => 'Return adjustment',
  CustomerLedgerType.adjustment => 'Manual adjustment',
};
