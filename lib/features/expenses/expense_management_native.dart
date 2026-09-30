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
import 'drift_expense_repository.dart';
import 'expense_models.dart';
import 'local_expense_service.dart';

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  State<ExpenseManagementScreen> createState() => _State();
}

class _State extends State<ExpenseManagementScreen> {
  AppDatabase? db;
  late Future<_Data> data = _open();
  final search = TextEditingController();
  String? category;
  DateTime? date;
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
    try {
      await widget.client.rpc(
        'ensure_default_expense_categories',
        params: {'p_shop_id': widget.shopId},
      );
    } catch (_) {}
    await pull();
    return load();
  }

  Future<void> pull() async {
    final p = ReferencePullService(
      db!,
      SupabaseReferencePullGateway(widget.client),
      shopId: widget.shopId,
    );
    for (final e in const [PullEntity.expenseCategories, PullEntity.expenses]) {
      try {
        await p.pull(e);
      } catch (_) {}
    }
  }

  Future<_Data> load() async {
    final r = DriftExpenseRepository(db!, shopId: widget.shopId);
    return _Data(
      await r.categories(),
      await r.query(
        search: search.text,
        categoryId: category,
        from: date,
        to: date,
      ),
    );
  }

  void refresh() => setState(() => data = load());
  @override
  void dispose() {
    search.dispose();
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Expenses'),
      actions: [
        IconButton(
          onPressed: customCategory,
          tooltip: 'Add category',
          icon: const Icon(Icons.category_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Add Expense'),
    ),
    body: FutureBuilder<_Data>(
      future: data,
      builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _total('Today', d.snapshot.todayMinor),
                  _total('This month', d.snapshot.monthMinor),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: search,
                      onChanged: (_) => refresh(),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search description/category',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String?>(
                      initialValue: category,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All categories'),
                        ),
                        ...d.categories.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        category = v;
                        refresh();
                      },
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: date ?? DateTime.now(),
                      );
                      if (mounted) refresh();
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(date == null ? 'Any date' : _date(date!)),
                  ),
                  if (date != null)
                    IconButton(
                      onPressed: () {
                        date = null;
                        refresh();
                      },
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ),
            Expanded(
              child: d.snapshot.rows.isEmpty
                  ? const Center(child: Text('No expenses found.'))
                  : ListView.builder(
                      itemCount: d.snapshot.rows.length,
                      itemBuilder: (_, i) {
                        final e = d.snapshot.rows[i];
                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(e.description),
                          subtitle: Text(
                            '${e.category} • ${e.paymentMethod.name} • ${_dateTime(e.expenseAt)}',
                          ),
                          trailing: Text(
                            formatPkr(e.amountMinor),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(e.description),
                              content: Text(
                                '${e.category}\n${formatPkr(e.amountMinor)} • ${e.paymentMethod.name}\n${_dateTime(e.expenseAt)}${e.reference == null ? '' : '\nReference: ${e.reference}'}${e.note == null ? '' : '\n${e.note}'}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
  Widget _total(String label, int value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Text(
            formatPkr(value),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
  Future<void> customCategory() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom category'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await widget.client.rpc(
        'create_expense_category',
        params: {'p_shop_id': widget.shopId, 'p_name': name},
      );
      await pull();
      refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category could not be created.')),
        );
      }
    }
  }

  Future<void> add() async {
    final categories = (await data).categories;
    if (!mounted) return;
    final draft = await showDialog<_Input>(
      context: context,
      builder: (_) => _ExpenseForm(categories: categories),
    );
    if (draft == null) return;
    try {
      await LocalExpenseService(
        db!,
        const UuidV7Generator(),
        authorizer: productionFinancialMutationAuthorizer(),
      ).create(
        ExpenseDraft(
          shopId: widget.shopId,
          categoryId: draft.category.id,
          categoryName: draft.category.name,
          amountMinor: draft.amount,
          paymentMethod: draft.method,
          description: draft.description,
          ownerId: widget.client.auth.currentUser!.id,
          deviceId: widget.deviceId,
          expenseAt: draft.date,
          note: draft.note,
          reference: draft.reference,
        ),
      );
      await SyncWorker(
        queue: SyncQueueRepository(db!, shopId: widget.shopId),
        gateway: SupabaseSaleUploadGateway(widget.client),
        workerId: 'owner-${widget.deviceId}',
      ).runOnce();
      refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Expense saved locally.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              safeUserMessage(
                e,
                fallback: 'Could not save the expense. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({required this.categories});
  final List<ExpenseCategoryModel> categories;
  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  ExpenseCategoryModel? category;
  PaymentMethod method = PaymentMethod.cash;
  DateTime date = DateTime.now();
  final amount = TextEditingController(),
      description = TextEditingController(),
      note = TextEditingController(),
      reference = TextEditingController();
  @override
  void dispose() {
    for (final c in [amount, description, note, reference]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Expense'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ExpenseCategoryModel>(
              initialValue: category,
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => category = v),
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Description *'),
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount *',
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
            ListTile(
              title: const Text('Expense date'),
              subtitle: Text(_date(date)),
              onTap: () async {
                final v = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDate: date,
                );
                if (v != null) setState(() => date = v);
              },
            ),
            TextField(
              controller: reference,
              decoration: const InputDecoration(labelText: 'Reference'),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final a = parseMoneyMinor(amount.text);
          if (category == null ||
              a == null ||
              a <= 0 ||
              description.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Complete all required fields.')),
            );
            return;
          }
          Navigator.pop(
            context,
            _Input(
              category!,
              a,
              method,
              date,
              description.text.trim(),
              _o(note.text),
              _o(reference.text),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

final class _Input {
  const _Input(
    this.category,
    this.amount,
    this.method,
    this.date,
    this.description,
    this.note,
    this.reference,
  );
  final ExpenseCategoryModel category;
  final int amount;
  final PaymentMethod method;
  final DateTime date;
  final String description;
  final String? note, reference;
}

final class _Data {
  const _Data(this.categories, this.snapshot);
  final List<ExpenseCategoryModel> categories;
  final ExpenseSnapshot snapshot;
}

String? _o(String s) => s.trim().isEmpty ? null : s.trim();
String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
String _dateTime(DateTime d) =>
    '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
