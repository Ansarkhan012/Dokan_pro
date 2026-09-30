import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/cashier_session_store.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../subscription/subscription_runtime.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../sync/pull/pull_models.dart';
import '../../sync/pull/reference_pull_service.dart';
import '../../sync/pull/supabase_reference_pull_gateway.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_worker.dart';
import '../pos/pos_state.dart';
import 'customer_gateway.dart';
import 'customer_khata_view.dart';
import 'customer_models.dart';
import 'drift_customer_repository.dart';
import 'local_customer_payment_service.dart';
import 'supabase_customer_gateway.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId, deviceId;
  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen>
    implements CustomerKhataActions {
  AppDatabase? db;
  late Future<List<CustomerAccount>> data = _open();
  final search = TextEditingController();
  bool refreshing = false;
  String? refreshWarning;
  CustomerGateway get gateway => SupabaseCustomerGateway(widget.client);
  Future<List<CustomerAccount>> _open() async {
    final database = db ?? await AppDatabase.open();
    db = database;
    // The tenant parent must exist before the local owner membership FK.
    try {
      await ReferencePullService(
        database,
        SupabaseReferencePullGateway(widget.client),
        shopId: widget.shopId,
      ).pull(PullEntity.shops);
    } catch (_) {
      final cachedShop = await (database.select(
        database.shops,
      )..where((row) => row.id.equals(widget.shopId))).getSingleOrNull();
      if (cachedShop == null) {
        throw StateError('Local shop bootstrap is incomplete');
      }
      refreshWarning =
          'Customers could not be refreshed. Showing available offline data.';
    }
    final userId = widget.client.auth.currentUser!.id;
    final now = DateTime.now().toUtc();
    await database
        .into(database.shopUsers)
        .insertOnConflictUpdate(
          ShopUsersCompanion.insert(
            id: 'owner-${widget.shopId}-$userId',
            shopId: widget.shopId,
            userId: userId,
            role: ShopRole.owner,
            createdAt: now,
          ),
        );
    await _pull();
    return searchCustomers('');
  }

  Future<void> _pull() async {
    final pull = ReferencePullService(
      db!,
      SupabaseReferencePullGateway(widget.client),
      shopId: widget.shopId,
    );
    for (final entity in const [
      PullEntity.customers,
      PullEntity.customerLedgerEntries,
    ]) {
      try {
        await pull.pull(entity);
      } catch (_) {
        refreshWarning =
            'Customers could not be refreshed. Showing available offline data.';
      }
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    await _pull();
    if (mounted) {
      setState(() {
        refreshing = false;
        data = searchCustomers(search.text);
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
  Future<List<CustomerAccount>> searchCustomers(String query) =>
      DriftCustomerRepository(db!, shopId: widget.shopId).search(query);
  @override
  Future<List<CustomerLedgerLine>> statement(String id) =>
      DriftCustomerRepository(db!, shopId: widget.shopId).statement(id);
  @override
  Future<void> receivePayment({
    required String customerId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {
    await LocalCustomerPaymentService(
      db!,
      const UuidV7Generator(),
      authorizer: productionFinancialMutationAuthorizer(),
    ).receive(
      shopId: widget.shopId,
      customerId: customerId,
      actorId: widget.client.auth.currentUser!.id,
      deviceId: widget.deviceId,
      amountMinor: amountMinor,
      method: method,
      reference: reference,
      note: note,
    );
    await _sync();
  }

  Future<void> _sync() async {
    await SyncWorker(
      queue: SyncQueueRepository(db!, shopId: widget.shopId),
      gateway: SupabaseSaleUploadGateway(widget.client),
      workerId: 'owner-${widget.deviceId}',
      cashierToken: () =>
          SecureCashierSessionStore().read().then((v) => v?.token),
    ).runOnce();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Customers / Khata'),
      actions: [
        IconButton(
          onPressed: refreshing ? null : refresh,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => edit(),
      icon: const Icon(Icons.person_add),
      label: const Text('Add customer'),
    ),
    body: Column(
      children: [
        if (refreshWarning != null)
          MaterialBanner(
            content: Text(refreshWarning!),
            actions: [
              TextButton(onPressed: refresh, child: const Text('Retry')),
            ],
          ),
        Expanded(
          child: FutureBuilder<List<CustomerAccount>>(
            future: data,
            builder: (context, snap) {
              if (!snap.hasData) {
                return snap.hasError
                    ? Center(
                        child: Text('Could not open customers: ${snap.error}'),
                      )
                    : const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data!;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: search,
                      onChanged: (v) =>
                          setState(() => data = searchCustomers(v)),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search name or phone',
                      ),
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text(
                              'No customers yet. Add the first customer.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final c = rows[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    c.name.substring(0, 1).toUpperCase(),
                                  ),
                                ),
                                title: Text(c.name),
                                subtitle: Text(
                                  '${c.phone ?? 'No phone'}${c.isActive ? '' : ' • Inactive'}',
                                ),
                                trailing: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      c.balanceMinor == 0
                                          ? 'Clear'
                                          : '${formatPkr(c.balanceMinor)} due',
                                    ),
                                    IconButton(
                                      onPressed: () => edit(c),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => CustomerDetailPage(
                                      customer: c,
                                      actions: this,
                                    ),
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
        ),
      ],
    ),
  );
  Future<void> edit([CustomerAccount? current]) async {
    final input = await showDialog<CustomerInput>(
      context: context,
      builder: (_) => _CustomerForm(current: current),
    );
    if (input == null) return;
    try {
      await gateway.saveCustomer(
        shopId: widget.shopId,
        customerId: current?.id,
        input: input,
      );
      await refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Customer saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer could not be saved.')),
        );
      }
    }
  }
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({this.current});
  final CustomerAccount? current;
  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  late final name = TextEditingController(text: widget.current?.name),
      phone = TextEditingController(text: widget.current?.phone),
      address = TextEditingController(text: widget.current?.address),
      notes = TextEditingController(text: widget.current?.notes),
      limit = TextEditingController(
        text: widget.current?.creditLimitMinor == null
            ? ''
            : minorToInput(widget.current!.creditLimitMinor!),
      );
  late bool active = widget.current?.isActive ?? true;
  String? error;
  @override
  void dispose() {
    for (final c in [name, phone, address, notes, limit]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.current == null ? 'Add customer' : 'Edit customer'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            TextField(
              controller: address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            TextField(
              controller: limit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Credit limit (optional)',
                prefixText: 'Rs ',
              ),
            ),
            SwitchListTile(
              value: active,
              onChanged: (v) => setState(() => active = v),
              title: const Text('Active'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          final credit = limit.text.trim().isEmpty
              ? null
              : parseMoneyMinor(limit.text);
          if (name.text.trim().isEmpty ||
              (limit.text.trim().isNotEmpty && credit == null)) {
            setState(
              () => error = 'Name and a valid credit limit are required.',
            );
            return;
          }
          Navigator.pop(
            context,
            CustomerInput(
              name: name.text.trim(),
              phone: _optional(phone.text),
              address: _optional(address.text),
              notes: _optional(notes.text),
              creditLimitMinor: credit,
              isActive: active,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
