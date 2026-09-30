import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/owner_cashier_setup_panel.dart';
import '../../core/domain/enums.dart';
import '../../database/app_database.dart';
import '../shop/cashier_admin_gateway.dart';
import '../shop/supabase_cashier_admin_gateway.dart';
import '../../subscription/entitlement_policy.dart';
import '../../subscription/entitlement_store.dart';
import '../../subscription/entitlement_verifier.dart';
import '../../subscription/supabase_entitlement_gateway.dart';

class OwnerSettingsScreen extends StatefulWidget {
  const OwnerSettingsScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId;
  final String deviceId;
  @override
  State<OwnerSettingsScreen> createState() => _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends State<OwnerSettingsScreen> {
  final name = TextEditingController(), phone = TextEditingController();
  final address = TextEditingController(), footer = TextEditingController();
  final threshold = TextEditingController(text: '0');
  AppDatabase? db;
  Shop? shop;
  List<Device> devices = const [];
  List<CashierMetadata> cashiers = const [];
  bool loading = true, saving = false;
  bool allowNegative = true, showPhone = true, showAddress = true;
  bool notifications = false;
  String paper = '80mm';
  String? error;
  EntitlementEvaluation? entitlement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _loadEntitlement();
    final database = await AppDatabase.open();
    db = database;
    var local = await (database.select(
      database.shops,
    )..where((row) => row.id.equals(widget.shopId))).getSingleOrNull();
    try {
      final raw = await widget.client
          .from('shops')
          .select()
          .eq('id', widget.shopId)
          .single();
      final updated = DateTime.parse(raw['updated_at'] as String).toUtc();
      await database
          .into(database.shops)
          .insertOnConflictUpdate(
            ShopsCompanion.insert(
              id: widget.shopId,
              name: raw['name'] as String,
              phone: raw['phone'] as String,
              address: raw['address'] as String,
              currency: Value(raw['currency'] as String),
              timezone: Value(raw['timezone'] as String),
              allowNegativeStock: Value(raw['allow_negative_stock'] as bool),
              defaultLowStockLevel: Value(
                (raw['default_low_stock_level'] as num).toInt(),
              ),
              receiptFooter: Value(raw['receipt_footer'] as String),
              receiptPaperWidth: Value(raw['receipt_paper_width'] as String),
              receiptShowPhone: Value(raw['receipt_show_phone'] as bool),
              receiptShowAddress: Value(raw['receipt_show_address'] as bool),
              notificationsEnabled: Value(raw['notifications_enabled'] as bool),
              subscriptionPlan: SubscriptionPlan.values.byName(
                raw['subscription_plan'] as String,
              ),
              subscriptionStatus: SubscriptionStatus.values.byName(
                raw['subscription_status'] as String,
              ),
              createdAt: DateTime.parse(raw['created_at'] as String).toUtc(),
              updatedAt: updated,
            ),
          );
      local = await (database.select(
        database.shops,
      )..where((r) => r.id.equals(widget.shopId))).getSingle();
      final remoteDevices = await widget.client
          .from('devices')
          .select()
          .eq('shop_id', widget.shopId);
      devices = remoteDevices
          .map(
            (r) => Device(
              id: r['id'] as String,
              shopId: widget.shopId,
              deviceName: r['device_name'] as String,
              deviceType: DeviceType.values.byName(r['device_type'] as String),
              deviceIdentifier: r['device_identifier'] as String,
              isActive: r['is_active'] as bool,
              lastSeenAt: r['last_seen_at'] == null
                  ? null
                  : DateTime.parse(r['last_seen_at'] as String),
              lastSyncedAt: r['last_synced_at'] == null
                  ? null
                  : DateTime.parse(r['last_synced_at'] as String),
              createdAt: DateTime.parse(r['created_at'] as String),
              updatedAt: r['updated_at'] == null
                  ? DateTime.parse(r['created_at'] as String)
                  : DateTime.parse(r['updated_at'] as String),
            ),
          )
          .toList();
      cashiers = await SupabaseCashierAdminGateway(
        widget.client,
      ).cashiers(shopId: widget.shopId);
    } catch (_) {
      devices = await (database.select(
        database.devices,
      )..where((r) => r.shopId.equals(widget.shopId))).get();
      cashiers =
          (await (database.select(
                database.cashiers,
              )..where((r) => r.shopId.equals(widget.shopId))).get())
              .map(
                (r) => CashierMetadata(
                  id: r.id,
                  displayName: r.displayName,
                  isActive: r.isActive,
                ),
              )
              .toList();
      error = local == null
          ? 'Settings are unavailable offline until the first sync.'
          : 'Showing cached settings.';
    }
    if (!mounted) return;
    if (local != null) _apply(local);
    setState(() {
      shop = local;
      loading = false;
    });
  }

  Future<void> _loadEntitlement() async {
    try {
      final store = SecureEntitlementStore();
      final verifier = EntitlementVerifier(rsaPublicKeyFromEnvironment());
      final policy = EntitlementPolicyService(verifier: verifier, store: store);
      var value = await policy.evaluate(
        shopId: widget.shopId,
        deviceId: widget.deviceId,
        localNow: DateTime.now(),
      );
      if (mounted) setState(() => entitlement = value);
      try {
        await SupabaseEntitlementGateway(
          widget.client,
          verifier,
          store,
        ).refresh(
          shopId: widget.shopId,
          deviceId: widget.deviceId,
          localNow: DateTime.now(),
        );
        value = await policy.evaluate(
          shopId: widget.shopId,
          deviceId: widget.deviceId,
          localNow: DateTime.now(),
        );
        if (mounted) setState(() => entitlement = value);
      } catch (_) {
        // A temporary refresh failure never discards a usable cached proof.
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => entitlement = const EntitlementEvaluation(
            EntitlementState.unavailable,
            MutationDecision.block,
            'Online subscription verification is required.',
          ),
        );
      }
    }
  }

  String _stateLabel(EntitlementState state) => switch (state) {
    EntitlementState.trialActive => 'Trial active',
    EntitlementState.active => 'Active',
    EntitlementState.expiringSoon => 'Expires soon',
    EntitlementState.offlineGrace => 'Offline grace',
    EntitlementState.clockVerificationRequired =>
      'Online verification required',
    EntitlementState.expired => 'Expired',
    EntitlementState.unavailable => 'Online verification required',
  };

  void _apply(Shop value) {
    name.text = value.name;
    phone.text = value.phone;
    address.text = value.address;
    footer.text = value.receiptFooter;
    threshold.text = '${value.defaultLowStockLevel}';
    allowNegative = value.allowNegativeStock;
    showPhone = value.receiptShowPhone;
    showAddress = value.receiptShowAddress;
    notifications = value.notificationsEnabled;
    paper = value.receiptPaperWidth;
  }

  Future<void> _save() async {
    final low = int.tryParse(threshold.text);
    if (name.text.trim().isEmpty || low == null || low < 0) {
      setState(
        () => error = 'Enter a shop name and a non-negative stock threshold.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final raw =
          await widget.client.rpc(
                'update_shop_settings',
                params: {
                  'p_shop_id': widget.shopId,
                  'p_name': name.text,
                  'p_phone': phone.text,
                  'p_address': address.text,
                  'p_allow_negative_stock': allowNegative,
                  'p_default_low_stock_level': low,
                  'p_receipt_footer': footer.text,
                  'p_receipt_paper_width': paper,
                  'p_receipt_show_phone': showPhone,
                  'p_receipt_show_address': showAddress,
                  'p_notifications_enabled': notifications,
                },
              )
              as Map<String, dynamic>;
      await (db!.update(
        db!.shops,
      )..where((r) => r.id.equals(widget.shopId))).write(
        ShopsCompanion(
          name: Value(raw['name'] as String),
          phone: Value(raw['phone'] as String),
          address: Value(raw['address'] as String),
          allowNegativeStock: Value(allowNegative),
          defaultLowStockLevel: Value(low),
          receiptFooter: Value(footer.text),
          receiptPaperWidth: Value(paper),
          receiptShowPhone: Value(showPhone),
          receiptShowAddress: Value(showAddress),
          notificationsEnabled: Value(notifications),
          updatedAt: Value(DateTime.parse(raw['updated_at'] as String).toUtc()),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save settings. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    footer.dispose();
    threshold.dispose();
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              Text(
                'Subscription',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (entitlement == null)
                const ListTile(title: Text('Checking subscription…'))
              else ...[
                ListTile(
                  title: Text(_stateLabel(entitlement!.state)),
                  subtitle: Text(entitlement!.message),
                ),
                ListTile(
                  title: const Text('Plan'),
                  subtitle: Text(entitlement!.claims?.planId ?? 'Unavailable'),
                ),
                if (entitlement!.claims case final claims?) ...[
                  ListTile(
                    title: const Text('Period ends'),
                    subtitle: Text(claims.validUntil.toLocal().toString()),
                  ),
                  ListTile(
                    title: const Text('Offline grace ends'),
                    subtitle: Text(
                      claims.offlineGraceUntil.toLocal().toString(),
                    ),
                  ),
                ],
                ListTile(
                  title: const Text('Last successful verification'),
                  subtitle: Text(
                    entitlement!.lastVerified?.toLocal().toString() ?? 'Never',
                  ),
                ),
                ListTile(
                  title: const Text('Device entitlement'),
                  subtitle: Text(
                    entitlement!.permitsMutation
                        ? 'Ready'
                        : 'Verification or renewal required',
                  ),
                ),
                OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Renewal/payment integration is not yet available.',
                      ),
                    ),
                  ),
                  child: const Text('Renew subscription'),
                ),
                const Divider(height: 40),
              ],
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Shop name'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const ListTile(
                title: Text('Currency'),
                subtitle: Text('PKR (fixed)'),
              ),
              const ListTile(
                title: Text('Timezone'),
                subtitle: Text('Asia/Karachi'),
              ),
              SwitchListTile(
                value: allowNegative,
                onChanged: (v) => setState(() => allowNegative = v),
                title: const Text('Allow negative stock'),
              ),
              TextField(
                controller: threshold,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Default low-stock threshold',
                ),
              ),
              TextField(
                controller: footer,
                decoration: const InputDecoration(labelText: 'Receipt footer'),
              ),
              DropdownButtonFormField(
                initialValue: paper,
                decoration: const InputDecoration(labelText: 'Paper width'),
                items: const [
                  DropdownMenuItem(value: '58mm', child: Text('58mm')),
                  DropdownMenuItem(value: '80mm', child: Text('80mm')),
                ],
                onChanged: (v) => setState(() => paper = v!),
              ),
              SwitchListTile(
                value: showPhone,
                onChanged: (v) => setState(() => showPhone = v),
                title: const Text('Show phone on receipt'),
              ),
              SwitchListTile(
                value: showAddress,
                onChanged: (v) => setState(() => showAddress = v),
                title: const Text('Show address on receipt'),
              ),
              SwitchListTile(
                value: notifications,
                onChanged: (v) => setState(() => notifications = v),
                title: const Text('Notifications preference'),
                subtitle: const Text(
                  'Preference only; push delivery is not configured.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'Saving…' : 'Save settings'),
              ),
              const Divider(height: 40),
              Text(
                'Registered devices',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final d in devices)
                ListTile(
                  title: Text(d.deviceName),
                  subtitle: Text(
                    '${d.deviceType.name} • Last sync ${d.lastSyncedAt?.toLocal() ?? 'Never'}',
                  ),
                  trailing: Text(d.isActive ? 'Active' : 'Inactive'),
                ),
              const Divider(height: 40),
              Text('Cashiers', style: Theme.of(context).textTheme.titleLarge),
              OwnerCashierSetupPanel(
                gateway: SupabaseCashierAdminGateway(widget.client),
                shopId: widget.shopId,
                cashiers: cashiers,
                onChanged: () async {
                  cashiers = await SupabaseCashierAdminGateway(
                    widget.client,
                  ).cashiers(shopId: widget.shopId);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
  );
}
