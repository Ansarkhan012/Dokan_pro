import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../subscription/entitlement_policy.dart';
import '../../subscription/subscription_runtime.dart';
import '../../core/errors/safe_error_message.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/sync_health.dart';
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
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';
import '../../core/l10n/messages.dart';

class PurchaseManagementScreen extends StatefulWidget {
  const PurchaseManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
    this.authorizer,
  });
  final SupabaseClient client;
  final String shopId, deviceId;

  /// Gate for saving financial records; null means the subscription-checked
  /// production authorizer (always, in the app). Tests inject one, as the
  /// local services themselves allow.
  final FinancialMutationAuthorizer? authorizer;
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
    // Block body: returning the Future made setState throw in debug builds,
    // so a saved purchase, supplier or payment was reported as failed.
    if (mounted) {
      setState(() {
        data = load();
      });
    }
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
      title: Text(context.l10n.ownerNavPurchases),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Row(
          children: [
            Expanded(child: _tab(context.l10n.purchasesTabSuppliers, 0)),
            Expanded(child: _tab(context.l10n.purchasesTabPurchases, 1)),
          ],
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: tab == 0 ? () => supplierForm() : () => newPurchase(),
      icon: const Icon(Icons.add),
      label: Text(
        tab == 0 ? context.l10n.suppliersAdd : context.l10n.purchasesNew,
      ),
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
                onChanged: (_) => setState(() {
                  data = load();
                }),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: tab == 0
                      ? context.l10n.suppliersSearch
                      : context.l10n.purchasesSearch,
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
      ? Center(child: Text(context.l10n.suppliersEmpty))
      : ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final s = rows[i];
            return ListTile(
              title: Text(bidiName(context, s.name)),
              subtitle: Text(
                '${s.phone == null ? context.l10n.khataNoPhone : bidiId(context, s.phone!)}'
                '${s.isActive ? '' : ' • ${context.l10n.productsInactive}'}',
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    context.l10n.suppliersPayable(
                      bidiMoney(context, formatPkr(s.payableMinor)),
                    ),
                  ),
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
      ? Center(child: Text(context.l10n.purchasesEmpty))
      : ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final p = rows[i];
            return ListTile(
              title: Text(
                '${bidiName(context, p.supplierName)} • '
                '${bidiMoney(context, formatPkr(p.totalMinor))}',
              ),
              subtitle: Text(
                context.l10n.purchaseRowDetails(
                  bidiId(context, _date(p.date)),
                  p.invoiceNumber == null
                      ? context.l10n.purchasesNoReference
                      : bidiId(context, p.invoiceNumber!),
                  '${p.itemCount}',
                ),
              ),
              trailing: Chip(
                label: Text(
                  p.status == PaymentStatus.paid
                      ? context.l10n.purchaseStatusPaid
                      : p.status == PaymentStatus.partiallyPaid
                      ? context.l10n.purchaseStatusPartial
                      : context.l10n.purchaseStatusCredit,
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
          SnackBar(content: Text(context.l10n.suppliersSaveFailed)),
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
                p.customName ??
                    masters[p.masterProductId]?.name ??
                    context.l10n.purchaseProductFallback,
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
        authorizer:
            widget.authorizer ?? productionFinancialMutationAuthorizer(),
      ).create(draft);
      await sync();
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.purchasesSaved)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizedMessage(
                context.l10n,
                safeUserMessage(
                  e,
                  fallback: 'Could not save the purchase. Please try again.',
                ),
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
      authorizer: widget.authorizer ?? productionFinancialMutationAuthorizer(),
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
    workerId: uniqueSyncWorkerId('owner-${widget.deviceId}'),
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
    title: Text(
      widget.current == null
          ? context.l10n.suppliersAdd
          : context.l10n.suppliersEdit,
    ),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in [
            (name, context.l10n.customerName),
            (contact, context.l10n.supplierContactPerson),
            (phone, context.l10n.customerPhone),
            (address, context.l10n.customerAddress),
            (notes, context.l10n.customerNotes),
          ])
            TextField(
              controller: f.$1,
              decoration: InputDecoration(labelText: f.$2),
            ),
          SwitchListTile(
            value: active,
            onChanged: (v) => setState(() => active = v),
            title: Text(context.l10n.editActive),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.commonCancel),
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
        child: Text(context.l10n.commonSave),
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
    appBar: AppBar(title: Text(context.l10n.purchasesNewTitle)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          initialValue: supplier,
          items: widget.suppliers
              .map(
                (s) => DropdownMenuItem(
                  value: s.id,
                  child: Text(bidiName(context, s.name)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => supplier = v),
          decoration: InputDecoration(
            labelText: context.l10n.purchaseSupplierRequired,
          ),
        ),
        TextField(
          controller: invoice,
          decoration: InputDecoration(
            labelText: context.l10n.purchaseInvoiceReference,
          ),
        ),
        TextField(
          controller: notes,
          decoration: InputDecoration(labelText: context.l10n.customerNotes),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.purchaseDate),
          subtitle: Text(bidiId(context, _date(purchaseDate))),
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
        Text(
          context.l10n.productsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final p in widget.products) _product(p),
        const Divider(),
        Text(
          context.l10n.receiptTotal(bidiMoney(context, formatPkr(total))),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        TextField(
          controller: paid,
          inputFormatters: const [AsciiDigitsFormatter()],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: context.l10n.purchaseAmountPaid,
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
        const SizedBox(height: 16),
        FilledButton(onPressed: save, child: Text(context.l10n.purchaseSave)),
      ],
    ),
  );
  Widget _product((ShopProduct, String) row) {
    final current = lines[row.$1.id];
    return ListTile(
      title: Text(productDisplayName(context, row.$2, productId: row.$1.id)),
      subtitle: current == null
          ? null
          : Text(
              context.l10n.purchaseLineQtyCost(
                bidiQuantity(context, quantityToInput(current.$1)),
                bidiMoney(context, formatPkr(current.$2)),
              ),
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
        SnackBar(content: Text(context.l10n.purchasesErrSelection)),
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
    title: Text(context.l10n.purchaseItemTitle),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: q,
          inputFormatters: const [AsciiDigitsFormatter()],
          decoration: InputDecoration(
            labelText: context.l10n.measureQuantityLabel,
          ),
        ),
        TextField(
          controller: c,
          inputFormatters: const [AsciiDigitsFormatter()],
          decoration: InputDecoration(labelText: context.l10n.purchaseUnitCost),
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
        child: Text(context.l10n.posAdd),
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
    appBar: AppBar(title: Text(bidiName(context, widget.supplier.name))),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: pay,
      icon: const Icon(Icons.payments),
      label: Text(context.l10n.khataRecordPayment),
    ),
    body: FutureBuilder<List<SupplierLedgerLine>>(
      future: lines,
      builder: (context, s) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.l10n.supplierPayableHeading(
              bidiMoney(context, formatPkr(widget.supplier.payableMinor)),
            ),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            context.l10n.supplierTotals(
              bidiMoney(
                context,
                formatPkr(widget.supplier.totalPurchasesMinor),
              ),
              bidiMoney(context, formatPkr(widget.supplier.totalPaymentsMinor)),
            ),
          ),
          const Divider(),
          for (final l in s.data ?? [])
            ListTile(
              title: Text(
                l.type == SupplierLedgerType.purchase
                    ? context.l10n.movementPurchase
                    : context.l10n.ledgerPayment,
              ),
              subtitle: Text(bidiId(context, _date(l.date))),
              trailing: Text(
                '${bidiMoney(context, '${l.signedAmountMinor > 0 ? '+' : '-'}${formatPkr(l.amountMinor)}')} • '
                '${bidiMoney(context, formatPkr(l.runningBalanceMinor))}',
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
      // A refused or failed payment used to escape unhandled with no message;
      // the owner now always sees whether it was recorded.
      try {
        await widget.onPay(v.$1, v.$2, v.$3, v.$4);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.supplierPaymentFailed)),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.supplierPaymentSaved)),
        );
        // Block body (see refresh): the statement now refreshes after a
        // payment instead of throwing in debug builds.
        setState(() {
          lines = widget.repo.statement(widget.supplier.id);
        });
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
    title: Text(context.l10n.supplierPaymentTitle),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: amount,
          inputFormatters: const [AsciiDigitsFormatter()],
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
          controller: ref,
          decoration: InputDecoration(labelText: context.l10n.commonReference),
        ),
        TextField(
          controller: note,
          decoration: InputDecoration(labelText: context.l10n.commonNote),
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
        child: Text(context.l10n.supplierPaymentRecord),
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
    appBar: AppBar(
      title: Text(
        purchase.invoiceNumber == null
            ? context.l10n.movementPurchase
            : bidiId(context, purchase.invoiceNumber!),
      ),
    ),
    body: FutureBuilder<List<PurchaseLineView>>(
      future: repo.purchaseLines(purchase.id),
      builder: (context, s) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            bidiName(context, purchase.supplierName),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            context.l10n.purchaseTotals(
              bidiMoney(context, formatPkr(purchase.totalMinor)),
              bidiMoney(context, formatPkr(purchase.paidMinor)),
              bidiMoney(context, formatPkr(purchase.dueMinor)),
            ),
          ),
          const Divider(),
          for (final l in s.data ?? [])
            ListTile(
              title: Text(productDisplayName(context, l.name)),
              subtitle: Text(
                '${bidiQuantity(context, quantityToInput(l.quantity))} × '
                '${bidiMoney(context, formatPkr(l.unitCostMinor))}',
              ),
              trailing: Text(bidiMoney(context, formatPkr(l.lineTotalMinor))),
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
  final m = RegExp(
    r'^(\d{1,9})(?:\.(\d{1,3}))?$',
  ).firstMatch(normalizeDigits(input).trim());
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
