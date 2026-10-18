import 'package:flutter/material.dart';
import '../../core/domain/enums.dart';
import '../pos/pos_state.dart';
import '../sales/domain/bill_reference.dart';
import 'customer_models.dart';
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/messages.dart';

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
      // Block body: a closure returning the Future makes setState throw in
      // debug builds (the list then never refreshed).
      setState(() {
        customers = widget.actions.searchCustomers(search.text);
      });
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
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: context.l10n.khataSearchLabel,
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<CustomerAccount>>(
          future: customers,
          builder: (context, snap) {
            if (!snap.hasData) {
              return snap.hasError
                  ? Center(
                      child: Text(
                        context.l10n.khataLoadFailed('${snap.error}'),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator());
            }
            if (snap.data!.isEmpty) {
              return Center(child: Text(context.l10n.khataNoCustomers));
            }
            return ListView.builder(
              itemCount: snap.data!.length,
              itemBuilder: (_, i) {
                final customer = snap.data![i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(customer.name.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(bidiName(context, customer.name)),
                  subtitle: Text(customerPhoneLine(context, customer)),
                  trailing: Text(
                    customerBalanceLabel(context, customer.balanceMinor),
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

  /// A payment is being recorded: a second tap must not record it twice.
  bool receiving = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(bidiName(context, widget.customer.name))),
    floatingActionButton: widget.customer.isActive
        ? FloatingActionButton.extended(
            onPressed: receiving ? null : receive,
            icon: const Icon(Icons.payments_outlined),
            label: Text(context.l10n.khataReceivePayment),
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
                    _metric(
                      context.l10n.khataBalance,
                      _money(context, widget.customer.balanceMinor),
                    ),
                    _metric(
                      context.l10n.khataCreditLimit,
                      widget.customer.creditLimitMinor == null
                          ? context.l10n.khataNotSet
                          : _money(context, widget.customer.creditLimitMinor!),
                    ),
                    _metric(
                      context.l10n.khataCreditSales,
                      _money(context, widget.customer.totalCreditMinor),
                    ),
                    _metric(
                      context.l10n.khataPayments,
                      _money(context, widget.customer.totalPaymentsMinor),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.khataStatement,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (snap.data!.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(context.l10n.khataNoEntries)),
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
                title: Text(_ledgerLabel(context, line)),
                subtitle: Text(
                  '${_date(line.createdAt)}${line.note == null ? '' : ' • ${bidiName(context, line.note!)}'}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      bidiMoney(
                        context,
                        '${line.signedAmountMinor >= 0 ? '+' : '-'}${formatPkr(line.amountMinor.abs())}',
                      ),
                    ),
                    Text(
                      context.l10n.khataRunningBalance(
                        _money(context, line.runningBalanceMinor),
                      ),
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
    if (receiving) return;
    setState(() => receiving = true);
    try {
      await _receive();
    } finally {
      if (mounted) setState(() => receiving = false);
    }
  }

  Future<void> _receive() async {
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
      // Block body: returning the Future made setState throw in debug
      // builds, so a saved payment was reported as "could not be recorded".
      setState(() {
        lines = widget.actions.statement(widget.customer.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.khataPaymentSaved)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.khataPaymentFailed)),
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
    title: Text(context.l10n.khataReceivePayment),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amount,
            inputFormatters: const [AsciiDigitsFormatter()],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.l10n.khataAmount,
              prefixText: 'Rs ',
            ),
          ),
          SegmentedButton<PaymentMethod>(
            segments: [
              ButtonSegment(
                value: PaymentMethod.cash,
                label: Text(context.l10n.paymentCash),
              ),
              ButtonSegment(
                value: PaymentMethod.digital,
                label: Text(context.l10n.paymentDigital),
              ),
            ],
            selected: {method},
            onSelectionChanged: (v) => setState(() => method = v.single),
          ),
          TextField(
            controller: reference,
            decoration: InputDecoration(
              labelText: context.l10n.khataReferenceOptional,
            ),
          ),
          TextField(
            controller: note,
            decoration: InputDecoration(
              labelText: context.l10n.khataNoteOptional,
            ),
          ),
          if (error != null)
            Text(
              localizedMessage(context.l10n, error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: Text(context.l10n.commonCancel),
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
        child: Text(context.l10n.khataRecordPayment),
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
String _ledgerLabel(BuildContext context, CustomerLedgerLine line) {
  final l10n = context.l10n;
  return switch (line.type) {
    CustomerLedgerType.creditSale =>
      '${l10n.ledgerSale}${line.saleId == null ? '' : ' • ${bidiId(context, billReference(line.saleId!))}'}',
    CustomerLedgerType.paymentReceived =>
      '${l10n.ledgerPayment}${line.paymentMethod == null ? '' : ' • ${l10n.paymentStored(line.paymentMethod!, line.paymentMethod!)}'}',
    CustomerLedgerType.openingBalance => l10n.ledgerOpeningBalance,
    CustomerLedgerType.refund => l10n.ledgerReturnAdjustment,
    CustomerLedgerType.adjustment => l10n.ledgerManualAdjustment,
  };
}

String _money(BuildContext context, int minor) =>
    bidiMoney(context, formatPkr(minor));

/// `0300 1234567` (or `No phone`), plus ` • Inactive`, in the UI language.
String customerPhoneLine(BuildContext context, CustomerAccount customer) {
  final phone = customer.phone;
  return '${phone == null ? context.l10n.khataNoPhone : bidiId(context, phone)}'
      '${customer.isActive ? '' : ' • ${context.l10n.productsInactive}'}';
}

/// `Clear`, or `Rs 1,200.00 due`, in the UI language.
String customerBalanceLabel(BuildContext context, int balanceMinor) =>
    balanceMinor == 0
    ? context.l10n.khataBalanceClear
    : context.l10n.khataDue(_money(context, balanceMinor));
