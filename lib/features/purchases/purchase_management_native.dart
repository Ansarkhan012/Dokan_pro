import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../subscription/subscription_runtime.dart';
import '../../core/errors/safe_error_message.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/pull/pull_models.dart';
import '../../sync/pull/reference_pull_service.dart';
import '../../sync/pull/supabase_reference_pull_gateway.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_worker.dart';
import '../pos/pos_state.dart';
import 'drift_purchase_repository.dart';
import 'local_purchase_service.dart';
import 'local_supplier_payment_service.dart';
import 'purchase_models.dart';
import 'supplier_gateway.dart';

class PurchaseManagementScreen extends StatefulWidget {
  const PurchaseManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  State<PurchaseManagementScreen> createState() => _State();
}

class _State extends State<PurchaseManagementScreen> {
  AppDatabase? db;
  late Future<_Data> data = _open();
  int tab = 0;
  final search = TextEditingController();
  Future<_Data> _open() async {
    db ??= await AppDatabase.open();
    final uid = widget.client.auth.currentUser!.id,
        now = DateTime.now().toUtc();
    await db!
        .into(db!.shopUsers)
        .insertOnConflictUpdate(
          ShopUsersCompanion.insert(
            id: 'owner-${widget.shopId}-$uid',
            shopId: widget.shopId,
            userId: uid,
            role: ShopRole.owner,
            createdAt: now,
          ),
        );
    await pull();
    return load();
  }

  Future<void> pull() async {
    final p = ReferencePullService(
      db!,
      SupabaseReferencePullGateway(widget.client),
      shopId: widget.shopId,
    );
    for (final e in const [
      PullEntity.suppliers,
      PullEntity.purchases,
      PullEntity.purchaseItems,
      PullEntity.purchasePayments,
      PullEntity.supplierLedgerEntries,
      PullEntity.inventoryMovements,
    ]) {
      try {
        await p.pull(e);
      } catch (_) {}
    }
  }

  Future<_Data> load() async {
    final r = DriftPurchaseRepository(db!, shopId: widget.shopId);
    return _Data(
      await r.suppliers(search.text),
      await r.purchases(query: search.text),
    );
  }

  Future<void> refresh() async {
    await pull();
    if (mounted) setState(() => data = load());
  }

  @override
  void dispose() {
    search.dispose();
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Suppliers & Purchases'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Row(
          children: [
            Expanded(child: _tab('Suppliers', 0)),
            Expanded(child: _tab('Purchases', 1)),
          ],
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: tab == 0 ? () => supplierForm() : () => newPurchase(),
      icon: const Icon(Icons.add),
      label: Text(tab == 0 ? 'Add supplier' : 'New purchase'),
    ),
    body: FutureBuilder<_Data>(
      future: data,
      builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() => data = load()),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: tab == 0
                      ? 'Search supplier name or phone'
                      : 'Search supplier or invoice',
                ),
              ),
            ),
            Expanded(
              child: tab == 0
                  ? _suppliers(s.data!.suppliers)
                  : _purchases(s.data!.purchases),
            ),
          ],
        );
      },
    ),
  );
  Widget _tab(String label, int value) => TextButton(
    onPressed: () => setState(() {
      tab = value;
      search.clear();
      data = load();
    }),
    child: Text(
      label,
      style: TextStyle(fontWeight: tab == value ? FontWeight.bold : null),
    ),
  );
  Widget _suppliers(List<SupplierAccount> rows) => rows.isEmpty
      ? const Center(child: Text('No suppliers yet.'))
      : ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final s = rows[i];
            return ListTile(
              title: Text(s.name),
              subtitle: Text(
                '${s.phone ?? 'No phone'}${s.isActive ? '' : ' • Inactive'}',
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${formatPkr(s.payableMinor)} payable'),
                  IconButton(
                    onPressed: () => supplierForm(s),
                    icon: const Icon(Icons.edit),
                  ),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _SupplierDetail(
                    supplier: s,
                    repo: DriftPurchaseRepository(db!, shopId: widget.shopId),
                    onPay: (amount, method, ref, note) =>
                        paySupplier(s, amount, method, ref, note),
                  ),
                ),
              ),
            );
          },
        );
  Widget _purchases(List<PurchaseSummary> rows) => rows.isEmpty
      ? const Center(child: Text('No purchases yet.'))
      : ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final p = rows[i];
            return ListTile(
              title: Text('${p.supplierName} • ${formatPkr(p.totalMinor)}'),
              subtitle: Text(
                '${_date(p.date)} • ${p.invoiceNumber ?? 'No reference'} • ${p.itemCount} items',
              ),
              trailing: Chip(
                label: Text(
                  p.status == PaymentStatus.paid
                      ? 'Paid'
                      : p.status == PaymentStatus.partiallyPaid
                      ? 'Partial'
                      : 'Credit',
                ),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _PurchaseDetail(
                    purchase: p,
                    repo: DriftPurchaseRepository(db!, shopId: widget.shopId),
                  ),
                ),
              ),
            );
          },
        );
  Future<void> supplierForm([SupplierAccount? s]) async {
    final input = await showDialog<SupplierInput>(
      context: context,
      builder: (_) => _SupplierForm(current: s),
    );
    if (input == null) return;
    try {
      await SupplierGateway(
        widget.client,
      ).save(shopId: widget.shopId, supplierId: s?.id, input: input);
      await refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier could not be saved.')),
        );
      }
    }
  }

  Future<void> newPurchase() async {
    final suppliers = await DriftPurchaseRepository(
      db!,
      shopId: widget.shopId,
    ).suppliers('', activeOnly: true);
    final products =
        await (db!.select(db!.shopProducts)..where(
              (t) => t.shopId.equals(widget.shopId) & t.isActive.equals(true),
            ))
            .get();
    final masters = {
      for (final m in await db!.select(db!.masterProducts).get()) m.id: m,
    };
    if (!mounted) return;
    final draft = await Navigator.push<PurchaseDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => _NewPurchase(
          shopId: widget.shopId,
          deviceId: widget.deviceId,
          ownerId: widget.client.auth.currentUser!.id,
          suppliers: suppliers,
          products: [
            for (final p in products)
              (
                p,
                p.customName ?? masters[p.masterProductId]?.name ?? 'Product',
              ),
          ],
        ),
      ),
    );
    if (draft == null) return;
    try {
      await LocalPurchaseService(
        db!,
        const UuidV7Generator(),
        authorizer: productionFinancialMutationAuthorizer(),
      ).create(draft);
      await sync();
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase saved locally.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              safeUserMessage(
                e,
                fallback: 'Could not save the purchase. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> paySupplier(
    SupplierAccount s,
    int amount,
    PaymentMethod method,
    String? ref,
    String? note,
  ) async {
    await LocalSupplierPaymentService(
      db!,
      const UuidV7Generator(),
      authorizer: productionFinancialMutationAuthorizer(),
    ).record(
      shopId: widget.shopId,
      supplierId: s.id,
      ownerId: widget.client.auth.currentUser!.id,
      deviceId: widget.deviceId,
      amountMinor: amount,
      method: method,
      reference: ref,
      note: note,
    );
    await sync();
    await refresh();
  }

  Future<void> sync() => SyncWorker(
    queue: SyncQueueRepository(db!, shopId: widget.shopId),
    gateway: SupabaseSaleUploadGateway(widget.client),
    workerId: 'owner-${widget.deviceId}',
  ).runOnce().then((_) {});
}

class _SupplierForm extends StatefulWidget {
  const _SupplierForm({this.current});
  final SupplierAccount? current;
  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> {
  late final name = TextEditingController(text: widget.current?.name),
      contact = TextEditingController(text: widget.current?.contactPerson),
      phone = TextEditingController(text: widget.current?.phone),
      address = TextEditingController(text: widget.current?.address),
      notes = TextEditingController(text: widget.current?.notes);
  late bool active = widget.current?.isActive ?? true;
  @override
  void dispose() {
    for (final c in [name, contact, phone, address, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.current == null ? 'Add supplier' : 'Edit supplier'),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in [
            (name, 'Name *'),
            (contact, 'Contact person'),
            (phone, 'Phone'),
            (address, 'Address'),
            (notes, 'Notes'),
          ])
            TextField(
              controller: f.$1,
              decoration: InputDecoration(labelText: f.$2),
            ),
          SwitchListTile(
            value: active,
            onChanged: (v) => setState(() => active = v),
            title: const Text('Active'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                SupplierInput(
                  name: name.text.trim(),
                  contactPerson: _o(contact.text),
                  phone: _o(phone.text),
                  address: _o(address.text),
                  notes: _o(notes.text),
                  isActive: active,
                ),
              ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _NewPurchase extends StatefulWidget {
  const _NewPurchase({
    required this.shopId,
    required this.deviceId,
    required this.ownerId,
    required this.suppliers,
    required this.products,
  });
  final String shopId, deviceId, ownerId;
  final List<SupplierAccount> suppliers;
  final List<(ShopProduct, String)> products;
  @override
  State<_NewPurchase> createState() => _NewPurchaseState();
}

class _NewPurchaseState extends State<_NewPurchase> {
  String? supplier;
  final invoice = TextEditingController(),
      notes = TextEditingController(),
      paid = TextEditingController(text: '0');
  PaymentMethod method = PaymentMethod.cash;
  DateTime purchaseDate = DateTime.now();
  final lines = <String, (int, int)>{};
  @override
  void dispose() {
    invoice.dispose();
    notes.dispose();
    paid.dispose();
    super.dispose();
  }

  int get total => lines.entries.fold(
    0,
    (sum, e) => sum + (e.value.$1 * e.value.$2 + 500) ~/ 1000,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Purchase')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          initialValue: supplier,
          items: widget.suppliers
              .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
              .toList(),
          onChanged: (v) => setState(() => supplier = v),
          decoration: const InputDecoration(labelText: 'Supplier *'),
        ),
        TextField(
          controller: invoice,
          decoration: const InputDecoration(labelText: 'Invoice/reference'),
        ),
        TextField(
          controller: notes,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Purchase date'),
          subtitle: Text(_date(purchaseDate)),
          trailing: const Icon(Icons.calendar_month),
          onTap: () async {
            final selected = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              initialDate: purchaseDate,
            );
            if (selected != null && mounted) {
              setState(() => purchaseDate = selected);
            }
          },
        ),
        const SizedBox(height: 16),
        Text('Products', style: Theme.of(context).textTheme.titleLarge),
        for (final p in widget.products) _product(p),
        const Divider(),
        Text(
          'Total ${formatPkr(total)}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        TextField(
          controller: paid,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount paid',
            prefixText: 'Rs ',
          ),
        ),
        SegmentedButton<PaymentMethod>(
          segments: const [
            ButtonSegment(value: PaymentMethod.cash, label: Text('Cash')),
            ButtonSegment(value: PaymentMethod.digital, label: Text('Digital')),
          ],
          selected: {method},
          onSelectionChanged: (v) => setState(() => method = v.single),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: save, child: const Text('Save Purchase')),
      ],
    ),
  );
  Widget _product((ShopProduct, String) row) {
    final current = lines[row.$1.id];
    return ListTile(
      title: Text(row.$2),
      subtitle: current == null
          ? null
          : Text(
              'Qty ${quantityToInput(current.$1)} @ ${formatPkr(current.$2)}',
            ),
      trailing: IconButton(
        icon: Icon(current == null ? Icons.add : Icons.edit),
        onPressed: () async {
          final v = await showDialog<(int, int)>(
            context: context,
            builder: (_) => _LineDialog(
              quantity: current?.$1,
              cost: current?.$2 ?? row.$1.purchasePrice,
            ),
          );
          if (v != null) setState(() => lines[row.$1.id] = v);
        },
      ),
    );
  }

  void save() {
    final paidMinor = parseMoneyMinor(paid.text);
    if (supplier == null ||
        lines.isEmpty ||
        paidMinor == null ||
        paidMinor > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select supplier/items and enter a valid payment.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      PurchaseDraft(
        shopId: widget.shopId,
        supplierId: supplier!,
        deviceId: widget.deviceId,
        ownerId: widget.ownerId,
        invoiceNumber: _o(invoice.text),
        notes: _o(notes.text),
        purchaseDate: purchaseDate,
        lines: [
          for (final e in lines.entries)
            PurchaseLineDraft(
              productId: e.key,
              quantity: e.value.$1,
              unitCostMinor: e.value.$2,
            ),
        ],
        payments: paidMinor == 0
            ? const []
            : [PurchasePaymentDraft(method: method, amountMinor: paidMinor)],
      ),
    );
  }
}

class _LineDialog extends StatefulWidget {
  const _LineDialog({this.quantity, required this.cost});
  final int? quantity;
  final int cost;
  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final q = TextEditingController(
        text: quantityToInput(widget.quantity ?? 1000),
      ),
      c = TextEditingController(text: minorToInput(widget.cost));
  @override
  void dispose() {
    q.dispose();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Purchase item'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: q,
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'Unit cost'),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () {
          final quantity = parseQuantity(q.text),
              cost = parseMoneyMinor(c.text);
          if (quantity != null && quantity > 0 && cost != null) {
            Navigator.pop(context, (quantity, cost));
          }
        },
        child: const Text('Add'),
      ),
    ],
  );
}

class _SupplierDetail extends StatefulWidget {
  const _SupplierDetail({
    required this.supplier,
    required this.repo,
    required this.onPay,
  });
  final SupplierAccount supplier;
  final DriftPurchaseRepository repo;
  final Future<void> Function(int, PaymentMethod, String?, String?) onPay;
  @override
  State<_SupplierDetail> createState() => _SupplierDetailState();
}

class _SupplierDetailState extends State<_SupplierDetail> {
  late Future<List<SupplierLedgerLine>> lines = widget.repo.statement(
    widget.supplier.id,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.supplier.name)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: pay,
      icon: const Icon(Icons.payments),
      label: const Text('Record Payment'),
    ),
    body: FutureBuilder<List<SupplierLedgerLine>>(
      future: lines,
      builder: (context, s) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Payable ${formatPkr(widget.supplier.payableMinor)}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            'Purchases ${formatPkr(widget.supplier.totalPurchasesMinor)} • Payments ${formatPkr(widget.supplier.totalPaymentsMinor)}',
          ),
          const Divider(),
          for (final l in s.data ?? [])
            ListTile(
              title: Text(
                l.type == SupplierLedgerType.purchase ? 'Purchase' : 'Payment',
              ),
              subtitle: Text(_date(l.date)),
              trailing: Text(
                '${l.signedAmountMinor > 0 ? '+' : '-'}${formatPkr(l.amountMinor)} • ${formatPkr(l.runningBalanceMinor)}',
              ),
            ),
        ],
      ),
    ),
  );
  Future<void> pay() async {
    final v = await showDialog<(int, PaymentMethod, String?, String?)>(
      context: context,
      builder: (_) => _PayDialog(maximumMinor: widget.supplier.payableMinor),
    );
    if (v != null) {
      await widget.onPay(v.$1, v.$2, v.$3, v.$4);
      if (mounted) {
        setState(() => lines = widget.repo.statement(widget.supplier.id));
      }
    }
  }
}

class _PayDialog extends StatefulWidget {
  const _PayDialog({required this.maximumMinor});
  final int maximumMinor;
  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  final amount = TextEditingController(),
      ref = TextEditingController(),
      note = TextEditingController();
  PaymentMethod method = PaymentMethod.cash;
  @override
  void dispose() {
    amount.dispose();
    ref.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Supplier Payment'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: amount,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: 'Rs ',
          ),
        ),
        SegmentedButton<PaymentMethod>(
          segments: const [
            ButtonSegment(value: PaymentMethod.cash, label: Text('Cash')),
            ButtonSegment(value: PaymentMethod.digital, label: Text('Digital')),
          ],
          selected: {method},
          onSelectionChanged: (v) => setState(() => method = v.single),
        ),
        TextField(
          controller: ref,
          decoration: const InputDecoration(labelText: 'Reference'),
        ),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () {
          final v = parseMoneyMinor(amount.text);
          if (v != null && v > 0 && v <= widget.maximumMinor) {
            Navigator.pop(context, (v, method, _o(ref.text), _o(note.text)));
          }
        },
        child: const Text('Record'),
      ),
    ],
  );
}

class _PurchaseDetail extends StatelessWidget {
  const _PurchaseDetail({required this.purchase, required this.repo});
  final PurchaseSummary purchase;
  final DriftPurchaseRepository repo;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(purchase.invoiceNumber ?? 'Purchase')),
    body: FutureBuilder<List<PurchaseLineView>>(
      future: repo.purchaseLines(purchase.id),
      builder: (context, s) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            purchase.supplierName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            'Total ${formatPkr(purchase.totalMinor)} • Paid ${formatPkr(purchase.paidMinor)} • Due ${formatPkr(purchase.dueMinor)}',
          ),
          const Divider(),
          for (final l in s.data ?? [])
            ListTile(
              title: Text(l.name),
              subtitle: Text(
                '${quantityToInput(l.quantity)} × ${formatPkr(l.unitCostMinor)}',
              ),
              trailing: Text(formatPkr(l.lineTotalMinor)),
            ),
        ],
      ),
    ),
  );
}

final class _Data {
  const _Data(this.suppliers, this.purchases);
  final List<SupplierAccount> suppliers;
  final List<PurchaseSummary> purchases;
}

String? _o(String s) => s.trim().isEmpty ? null : s.trim();
String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
int? parseQuantity(String input) {
  final m = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(input.trim());
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final fraction = (m.group(2) ?? '').padRight(3, '0');
  return whole * 1000 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

String quantityToInput(int value) {
  final whole = value ~/ 1000, fraction = value.abs() % 1000;
  return fraction == 0
      ? '$whole'
      : '$whole.${fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
}
