import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/owner_cashier_setup_panel.dart';
import '../../core/domain/enums.dart';
import '../../core/format/display_format.dart';
import '../../core/ui/pos_ui.dart';
import '../../database/app_database.dart';
import '../shop/cashier_admin_gateway.dart';
import '../shop/supabase_cashier_admin_gateway.dart';
import '../../subscription/entitlement_policy.dart';
import '../../subscription/entitlement_store.dart';
import '../../subscription/entitlement_verifier.dart';
import '../../subscription/supabase_entitlement_gateway.dart';
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/localized_format.dart';
import '../../core/l10n/messages.dart';
import '../../core/l10n/locale_controller.dart';
import 'offline_translation_setting.dart';
import '../app_update/app_update_host.dart';

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

  String _stateLabel(EntitlementState state) {
    final l10n = context.l10n;
    return switch (state) {
      EntitlementState.trialActive => l10n.subStateTrial,
      EntitlementState.active => l10n.editActive,
      EntitlementState.expiringSoon => l10n.subStateExpiringSoon,
      EntitlementState.offlineGrace => l10n.subStateOfflineGrace,
      EntitlementState.clockVerificationRequired => l10n.subStateVerify,
      EntitlementState.expired => l10n.subStateExpired,
      EntitlementState.revoked => l10n.subStateBlocked,
      EntitlementState.unavailable => l10n.subStateVerify,
    };
  }

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
    final low = int.tryParse(normalizeDigits(threshold.text));
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
        ).showSnackBar(SnackBar(content: Text(context.l10n.settingsSaved)));
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
    appBar: AppBar(title: Text(context.l10n.ownerNavSettings)),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Theme(
            data: posFormTheme(Theme.of(context)),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth > 872
                    ? (constraints.maxWidth - 840) / 2
                    : 16.0;
                return ListView(
                  padding: EdgeInsets.fromLTRB(side, 16, side, 32),
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          localizedMessage(context.l10n, error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    _section(
                      context,
                      context.l10n.settingsSubscription,
                      _subscription(),
                    ),
                    _section(
                      context,
                      context.l10n.languageMenuTooltip,
                      const _LanguageSetting(),
                    ),
                    _section(
                      context,
                      context.l10n.offlineTranslationHeading,
                      const OfflineTranslationSetting(),
                    ),
                    _section(
                      context,
                      context.l10n.settingsShopDetails,
                      Column(
                        children: [
                          TextField(
                            controller: name,
                            decoration: InputDecoration(
                              labelText: context.l10n.settingsShopName,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FieldPair(
                            TextField(
                              controller: phone,
                              inputFormatters: const [AsciiDigitsFormatter()],
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: context.l10n.customerPhone,
                              ),
                            ),
                            TextField(
                              controller: address,
                              decoration: InputDecoration(
                                labelText: context.l10n.customerAddress,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _InfoRow(context.l10n.settingsCurrency, 'PKR'),
                          _InfoRow(
                            context.l10n.settingsTimeZone,
                            context.l10n.settingsTimeZoneValue,
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      context.l10n.settingsStock,
                      Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: allowNegative,
                            onChanged: (v) => setState(() => allowNegative = v),
                            title: Text(context.l10n.settingsAllowNegative),
                          ),
                          TextField(
                            controller: threshold,
                            inputFormatters: const [AsciiDigitsFormatter()],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.l10n.settingsDefaultLowStock,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      context.l10n.receiptTitle,
                      Column(
                        children: [
                          FieldPair(
                            TextField(
                              controller: footer,
                              decoration: InputDecoration(
                                labelText: context.l10n.settingsReceiptFooter,
                              ),
                            ),
                            DropdownButtonFormField(
                              initialValue: paper,
                              decoration: InputDecoration(
                                labelText: context.l10n.settingsPaperWidth,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: '58mm',
                                  child: Text('58 mm'),
                                ),
                                DropdownMenuItem(
                                  value: '80mm',
                                  child: Text('80 mm'),
                                ),
                              ],
                              onChanged: (v) => setState(() => paper = v!),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: showPhone,
                            onChanged: (v) => setState(() => showPhone = v),
                            title: Text(context.l10n.settingsShowPhone),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: showAddress,
                            onChanged: (v) => setState(() => showAddress = v),
                            title: Text(context.l10n.settingsShowAddress),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      context.l10n.settingsNotifications,
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: notifications,
                        onChanged: (v) => setState(() => notifications = v),
                        title: Text(context.l10n.settingsOwnerAlerts),
                        // Honest: the preference is stored, alerts are not
                        // delivered yet.
                        subtitle: Text(context.l10n.settingsAlertsHint),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        onPressed: saving ? null : _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(160, 48),
                        ),
                        child: Text(
                          saving
                              ? context.l10n.commonSaving
                              : context.l10n.settingsSave,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(context, context.l10n.settingsDevices, _devices()),
                    if (AppUpdateHost.current case final updates?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed: updates.checkNow,
                            icon: const Icon(Icons.system_update_alt),
                            label: Text(context.l10n.updateCheckNow),
                          ),
                        ),
                      ),
                    _section(
                      context,
                      context.l10n.settingsCashiers,
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
                    ),
                  ],
                );
              },
            ),
          ),
  );

  Widget _section(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: PosCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [FormSectionLabel(title), child],
      ),
    ),
  );

  Widget _subscription() {
    final value = entitlement;
    final l10n = context.l10n;
    if (value == null) return Text(l10n.settingsCheckingSubscription);
    final claims = value.claims;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _stateLabel(value.state),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            value.permitsMutation
                ? StatusPill(
                    l10n.subCanRecord,
                    tone: StatusTone.success,
                    icon: Icons.check_circle_outline,
                  )
                : StatusPill(
                    l10n.subNeedsRenewal,
                    tone: StatusTone.danger,
                    icon: Icons.lock_outline,
                  ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          localizedMessage(l10n, value.message),
          style: const TextStyle(color: posMuted),
        ),
        const SizedBox(height: 8),
        _InfoRow(
          l10n.subPlan,
          claims == null
              ? l10n.subUnavailable
              : bidiName(context, humanizeIdentifier(claims.planId)),
        ),
        if (claims != null) ...[
          _InfoRow(l10n.subPeriodEnds, localizedDate(l10n, claims.validUntil)),
          _InfoRow(
            l10n.subOfflineUntil,
            localizedRelativeDateTime(l10n, claims.offlineGraceUntil),
          ),
        ],
        _InfoRow(
          l10n.subLastChecked,
          value.lastVerified == null
              ? l10n.subNotYet
              : localizedRelativeDateTime(l10n, value.lastVerified!),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.subRenewUnavailable))),
            child: Text(l10n.subRenew),
          ),
        ),
      ],
    );
  }

  /// Registered devices. `devices.last_synced_at` is never written by the
  /// server or app, so it is not shown: it read "Never" even for a device
  /// whose sales had synced. The status chip on the POS reflects this
  /// tablet's own upload queue instead.
  Widget _devices() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final d in devices)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                d.deviceType == DeviceType.windowsDesktop
                    ? Icons.desktop_windows_outlined
                    : d.deviceType == DeviceType.androidTablet
                    ? Icons.tablet_android_outlined
                    : Icons.smartphone_outlined,
                color: posMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.id == widget.deviceId
                          ? context.l10n.deviceThisDevice(
                              bidiName(context, d.deviceName),
                            )
                          : bidiName(context, d.deviceName),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      context.l10n.deviceRegistered(
                        _deviceTypeLabel(d.deviceType),
                        localizedDate(context.l10n, d.createdAt),
                      ),
                      style: const TextStyle(color: posMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              d.isActive
                  ? StatusPill(
                      context.l10n.editActive,
                      tone: StatusTone.success,
                    )
                  : StatusPill(
                      context.l10n.productsInactive,
                      tone: StatusTone.neutral,
                    ),
            ],
          ),
        ),
      const SizedBox(height: 4),
      Text(
        context.l10n.settingsSyncHint,
        style: const TextStyle(color: posMuted, fontSize: 12),
      ),
    ],
  );

  String _deviceTypeLabel(DeviceType type) => switch (type) {
    DeviceType.androidTablet => context.l10n.deviceAndroidTablet,
    DeviceType.windowsDesktop => context.l10n.deviceWindows,
    DeviceType.mobile => context.l10n.deviceMobile,
    _ => humanizeIdentifier(type.name),
  };
}

/// Device language (English / اردو) and the Urdu font, saved on this device
/// only. Switching keeps the owner signed in and this screen open.
class _LanguageSetting extends StatelessWidget {
  const _LanguageSetting();

  @override
  Widget build(BuildContext context) {
    final controller = LocaleScope.maybeOf(context);
    final l10n = context.l10n;
    if (controller == null) return Text(l10n.settingsLanguageHint);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          key: const ValueKey('settings-language'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
            ButtonSegment(value: 'ur', label: Text(l10n.languageUrdu)),
          ],
          selected: {controller.locale.languageCode},
          onSelectionChanged: (value) => controller.setLocale(
            value.single == 'ur'
                ? LocaleController.urdu
                : LocaleController.english,
          ),
        ),
        if (controller.isUrdu) ...[
          const SizedBox(height: 10),
          Text(l10n.urduFontHeading, style: const TextStyle(color: posMuted)),
          const SizedBox(height: 6),
          SegmentedButton<UrduFont>(
            key: const ValueKey('settings-urdu-font'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: UrduFont.nastaliq,
                label: Text(l10n.urduFontNastaliq),
              ),
              ButtonSegment(
                value: UrduFont.naskh,
                label: Text(l10n.urduFontNaskh),
              ),
            ],
            selected: {controller.urduFont},
            onSelectionChanged: (value) => controller.setUrduFont(value.single),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          l10n.settingsLanguageHint,
          style: const TextStyle(color: posMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: posMuted)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
