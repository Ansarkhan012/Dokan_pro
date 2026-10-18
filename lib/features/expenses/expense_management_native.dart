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
import 'drift_expense_repository.dart';
import 'expense_models.dart';
import 'local_expense_service.dart';
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/messages.dart';
import 'expense_category_l10n.dart';

class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({
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

  // Block body: returning the Future made setState throw in debug builds,
  // so a saved expense was reported as "Could not save the expense".
  void refresh() => setState(() {
    data = load();
  });
  @override
  void dispose() {
    search.dispose();
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.ownerNavExpenses),
      actions: [
        IconButton(
          onPressed: customCategory,
          tooltip: context.l10n.expensesAddCategory,
          icon: const Icon(Icons.category_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: Text(context.l10n.expensesAdd),
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
                  _total(context.l10n.billsToday, d.snapshot.todayMinor),
                  _total(context.l10n.expensesThisMonth, d.snapshot.monthMinor),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: search,
                      onChanged: (_) => refresh(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: context.l10n.expensesSearch,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String?>(
                      initialValue: category,
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(context.l10n.productsAllCategories),
                        ),
                        ...d.categories.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              _categoryName(context, c, shopId: widget.shopId),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        category = v;
                        refresh();
                      },
                      decoration: InputDecoration(
                        labelText: context.l10n.productsCategoryLabel,
                      ),
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
                    label: Text(
                      date == null
                          ? context.l10n.expensesAnyDate
                          : bidiId(context, _date(date!)),
                    ),
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
                  ? Center(child: Text(context.l10n.expensesEmpty))
                  : ListView.builder(
                      itemCount: d.snapshot.rows.length,
                      itemBuilder: (_, i) {
                        final e = d.snapshot.rows[i];
                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(bidiName(context, e.description)),
                          subtitle: Text(
                            '${bidiName(context, e.category)} • '
                            '${_method(context, e.paymentMethod)} • '
                            '${bidiId(context, _dateTime(e.expenseAt))}',
                          ),
                          trailing: Text(
                            bidiMoney(context, formatPkr(e.amountMinor)),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(bidiName(context, e.description)),
                              content: Text(
                                '${bidiName(context, e.category)}\n'
                                '${bidiMoney(context, formatPkr(e.amountMinor))} • '
                                '${_method(context, e.paymentMethod)}\n'
                                '${bidiId(context, _dateTime(e.expenseAt))}'
                                '${e.reference == null ? '' : '\n${context.l10n.expensesReferenceLine(bidiName(context, e.reference!))}'}'
                                '${e.note == null ? '' : '\n${bidiName(context, e.note!)}'}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(context.l10n.commonClose),
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
            bidiMoney(context, formatPkr(value)),
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
        title: Text(context.l10n.expensesCustomCategory),
        content: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: context.l10n.expensesCategoryName,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: Text(context.l10n.posAdd),
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
          SnackBar(content: Text(context.l10n.expensesCategoryFailed)),
        );
      }
    }
  }

  Future<void> add() async {
    final categories = (await data).categories;
    if (!mounted) return;
    final draft = await showDialog<_Input>(
      context: context,
      builder: (_) =>
          _ExpenseForm(categories: categories, shopId: widget.shopId),
    );
    if (draft == null) return;
    try {
      await LocalExpenseService(
        db!,
        const UuidV7Generator(),
        authorizer:
            widget.authorizer ?? productionFinancialMutationAuthorizer(),
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
        workerId: uniqueSyncWorkerId('owner-${widget.deviceId}'),
      ).runOnce();
      refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.expensesSaved)));
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
                  fallback: 'Could not save the expense. Please try again.',
                ),
              ),
            ),
          ),
        );
      }
    }
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({required this.categories, required this.shopId});
  final List<ExpenseCategoryModel> categories;
  final String shopId;
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
    title: Text(context.l10n.expensesAdd),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ExpenseCategoryModel>(
              initialValue: category,
              items: widget.categories
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        _categoryName(context, c, shopId: widget.shopId),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => category = v),
              decoration: InputDecoration(
                labelText: context.l10n.customCategoryRequired,
              ),
            ),
            TextField(
              controller: description,
              decoration: InputDecoration(
                labelText: context.l10n.expenseDescriptionRequired,
              ),
            ),
            TextField(
              controller: amount,
              inputFormatters: const [AsciiDigitsFormatter()],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.l10n.expenseAmountRequired,
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
            ListTile(
              title: Text(context.l10n.expenseDate),
              subtitle: Text(bidiId(context, _date(date))),
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
              decoration: InputDecoration(
                labelText: context.l10n.commonReference,
              ),
            ),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: context.l10n.commonNote),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.commonCancel),
      ),
      FilledButton(
        onPressed: () {
          final a = parseMoneyMinor(amount.text);
          if (category == null ||
              a == null ||
              a <= 0 ||
              description.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.expensesErrRequired)),
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
        child: Text(context.l10n.commonSave),
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

/// Default categories translated by their stable id in [shopId]; the shop's
/// own categories exactly as entered.
String _categoryName(
  BuildContext context,
  ExpenseCategoryModel category, {
  required String shopId,
}) => bidiName(
  context,
  localizedExpenseCategory(
    context.l10n,
    shopId: shopId,
    id: category.id,
    name: category.name,
  ),
);

final class _Data {
  const _Data(this.categories, this.snapshot);
  final List<ExpenseCategoryModel> categories;
  final ExpenseSnapshot snapshot;
}

String? _o(String s) => s.trim().isEmpty ? null : s.trim();

/// A payment method as stored (`cash`), translated in Urdu.
String _method(BuildContext context, PaymentMethod method) =>
    context.l10n.paymentStored(method.name, method.name);
String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
String _dateTime(DateTime d) =>
    '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
