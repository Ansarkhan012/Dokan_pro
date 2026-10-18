import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'admin_gateway.dart';
import '../core/device/device_code.dart';
import '../core/images/product_image_url.dart';
import '../features/products/product_image_picker.dart';
import '../features/products/product_management_models.dart' show ProductUnit;

/// Private Dokan Pro platform administration panel. Not part of the shop
/// app: it has its own entry point (admin_main.dart) and is never reachable
/// from the POS. The UI hides nothing for security; the server refuses every
/// admin call from a non-admin.
class AdminApp extends StatelessWidget {
  const AdminApp({
    super.key,
    required this.gateway,
    this.photoPicker = const GalleryProductImagePicker(),
    this.preparePhoto = prepareCatalogPhoto,
  });
  final AdminGateway gateway;
  final ProductImagePicker photoPicker;
  final CatalogPhotoPreparer preparePhoto;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dokan Pro Admin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: AdminRoot(
      gateway: gateway,
      photoPicker: photoPicker,
      preparePhoto: preparePhoto,
    ),
  );
}

String _date(DateTime? v) {
  if (v == null) return '—';
  final l = v.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

String _dateTime(DateTime v) {
  final l = v.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${_date(v)} ${two(l.hour)}:${two(l.minute)}';
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Runs an admin action, reports success or the server's reason.
Future<bool> _run(
  BuildContext context,
  Future<void> Function() action,
  String done,
) async {
  try {
    await action();
    if (context.mounted) _snack(context, done);
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, adminErrorText(e));
    return false;
  }
}

class AdminRoot extends StatefulWidget {
  const AdminRoot({
    super.key,
    required this.gateway,
    this.photoPicker = const GalleryProductImagePicker(),
    this.preparePhoto = prepareCatalogPhoto,
  });
  final AdminGateway gateway;
  final ProductImagePicker photoPicker;
  final CatalogPhotoPreparer preparePhoto;
  @override
  State<AdminRoot> createState() => _AdminRootState();
}

enum _Stage { loading, login, enroll, challenge, home }

/// Password sign-in is only the first step: the admin pages open only when
/// the server reports an AAL2 session (verified TOTP). The server enforces
/// the same on every admin call; this flow just leads the admin there.
class _AdminRootState extends State<AdminRoot> {
  _Stage stage = _Stage.loading;
  String? email, factorId, notice;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => stage = _Stage.loading);
    try {
      final current = await widget.gateway.currentEmail();
      if (current == null) return _toLogin();
      switch (await widget.gateway.access()) {
        case AdminAccess.none:
          await widget.gateway.signOut();
          return _toLogin('This account is not a platform administrator.');
        case AdminAccess.granted:
          if (mounted) {
            setState(() {
              email = current;
              stage = _Stage.home;
            });
          }
        case AdminAccess.mfaRequired:
          final factor = await widget.gateway.verifiedTotpFactorId();
          if (mounted) {
            setState(() {
              email = current;
              factorId = factor;
              stage = factor == null ? _Stage.enroll : _Stage.challenge;
            });
          }
      }
    } catch (_) {
      await _signOutQuietly();
      _toLogin('Your session ended. Sign in again.');
    }
  }

  Future<void> _signOutQuietly() async {
    try {
      await widget.gateway.signOut();
    } catch (_) {}
  }

  void _toLogin([String? message]) {
    if (!mounted) return;
    setState(() {
      stage = _Stage.login;
      email = null;
      factorId = null;
      notice = message;
    });
  }

  Future<void> _cancel() async {
    await _signOutQuietly();
    _toLogin('Sign-in cancelled.');
  }

  void _sessionEnded() => _toLogin('Your session ended. Sign in again.');

  @override
  Widget build(BuildContext context) => switch (stage) {
    _Stage.loading => const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    _Stage.login => AdminLoginPage(
      gateway: widget.gateway,
      notice: notice,
      onSignedIn: _check,
    ),
    _Stage.enroll => AdminMfaEnrollPage(
      gateway: widget.gateway,
      email: email!,
      onVerified: _check,
      onCancel: _cancel,
      onSessionEnded: _sessionEnded,
    ),
    _Stage.challenge => AdminMfaChallengePage(
      gateway: widget.gateway,
      factorId: factorId!,
      email: email!,
      onVerified: _check,
      onCancel: _cancel,
      onSessionEnded: _sessionEnded,
    ),
    _Stage.home => AdminHome(
      gateway: widget.gateway,
      email: email!,
      photoPicker: widget.photoPicker,
      preparePhoto: widget.preparePhoto,
      onSignOut: () async {
        await _signOutQuietly();
        _toLogin();
      },
    ),
  };
}

final _sixDigits = RegExp(r'^\d{6}$');

/// Shared 6-digit code entry for enrolment and sign-in challenges.
class _CodeForm extends StatefulWidget {
  const _CodeForm({
    required this.gateway,
    required this.factorId,
    required this.onVerified,
    required this.onCancel,
    required this.onSessionEnded,
  });
  final AdminGateway gateway;
  final String factorId;
  final VoidCallback onVerified, onCancel, onSessionEnded;
  @override
  State<_CodeForm> createState() => _CodeFormState();
}

class _CodeFormState extends State<_CodeForm> {
  final code = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> submit() async {
    final value = code.text.trim();
    if (!_sixDigits.hasMatch(value)) {
      setState(() => error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.gateway.verifyTotp(widget.factorId, value);
      if (await widget.gateway.access() != AdminAccess.granted) {
        throw StateError('session not elevated');
      }
      widget.onVerified();
    } catch (e) {
      final failure = mfaFailure(e);
      if (failure == MfaFailure.sessionEnded) {
        widget.onSessionEnded();
        return;
      }
      code.clear();
      if (mounted) setState(() => error = mfaFailureText(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(labelText: '6-digit code'),
        onSubmitted: (_) => busy ? null : submit(),
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? 'Verifying…' : 'Verify'),
      ),
      TextButton(
        onPressed: busy ? null : widget.onCancel,
        child: const Text('Cancel and sign out'),
      ),
    ],
  );
}

Widget _card(BuildContext context, String title, List<Widget> children) =>
    Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// Signed in with a password, admin listed, no authenticator yet: admin
/// access stays closed until a TOTP factor is enrolled and verified.
class AdminMfaEnrollPage extends StatefulWidget {
  const AdminMfaEnrollPage({
    super.key,
    required this.gateway,
    required this.email,
    required this.onVerified,
    required this.onCancel,
    required this.onSessionEnded,
  });
  final AdminGateway gateway;
  final String email;
  final VoidCallback onVerified, onCancel, onSessionEnded;
  @override
  State<AdminMfaEnrollPage> createState() => _AdminMfaEnrollPageState();
}

class _AdminMfaEnrollPageState extends State<AdminMfaEnrollPage> {
  TotpEnrollment? enrollment;
  String? error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => error = null);
    try {
      final e = await widget.gateway.enrollTotp();
      if (mounted) setState(() => enrollment = e);
    } catch (e) {
      final failure = mfaFailure(e);
      if (failure == MfaFailure.sessionEnded) return widget.onSessionEnded();
      if (mounted) setState(() => error = mfaFailureText(failure));
    }
  }

  Future<void> _cancel() async {
    final e = enrollment;
    if (e != null) {
      try {
        await widget.gateway.cancelEnrollment(e.factorId);
      } catch (_) {}
    }
    widget.onCancel();
  }

  /// "ABCD EFGH ..." is easier to type into an authenticator app.
  static String _grouped(String secret) => [
    for (var i = 0; i < secret.length; i += 4)
      secret.substring(i, i + 4 > secret.length ? secret.length : i + 4),
  ].join(' ');

  @override
  Widget build(BuildContext context) {
    final e = enrollment;
    return _card(context, 'Set up two-step verification', [
      Text(
        '${widget.email} is a platform administrator. Admin access requires '
        'an authenticator app (Google Authenticator, Microsoft Authenticator '
        'or similar).',
      ),
      const SizedBox(height: 12),
      if (error != null) ...[
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(onPressed: _start, child: const Text('Try again')),
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('Cancel and sign out'),
        ),
      ] else if (e == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        const Text(
          '1. In the authenticator app choose "Add account", then "Enter a '
          'setup key". Account name: Dokan Pro Admin. Type: time-based.',
        ),
        const SizedBox(height: 8),
        SelectableText(
          _grouped(e.secret),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        const Text('2. Enter the 6-digit code the app shows.'),
        const SizedBox(height: 8),
        _CodeForm(
          gateway: widget.gateway,
          factorId: e.factorId,
          onVerified: widget.onVerified,
          onCancel: _cancel,
          onSessionEnded: widget.onSessionEnded,
        ),
      ],
    ]);
  }
}

/// Signed in with a password and an authenticator exists: one more code.
class AdminMfaChallengePage extends StatelessWidget {
  const AdminMfaChallengePage({
    super.key,
    required this.gateway,
    required this.factorId,
    required this.email,
    required this.onVerified,
    required this.onCancel,
    required this.onSessionEnded,
  });
  final AdminGateway gateway;
  final String factorId, email;
  final VoidCallback onVerified, onCancel, onSessionEnded;

  @override
  Widget build(BuildContext context) =>
      _card(context, 'Two-step verification', [
        Text('Enter the code from your authenticator app for $email.'),
        const SizedBox(height: 8),
        _CodeForm(
          gateway: gateway,
          factorId: factorId,
          onVerified: onVerified,
          onCancel: onCancel,
          onSessionEnded: onSessionEnded,
        ),
      ]);
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({
    super.key,
    required this.gateway,
    required this.onSignedIn,
    this.notice,
  });
  final AdminGateway gateway;
  final VoidCallback onSignedIn;
  final String? notice;
  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  late String? error = widget.notice;
  bool busy = false;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.gateway.signIn(email.text.trim(), password.text);
      if (await widget.gateway.access() == AdminAccess.none) {
        await widget.gateway.signOut();
        setState(() => error = 'This account is not a platform administrator.');
        return;
      }
      widget.onSignedIn();
    } catch (e) {
      setState(() => error = adminErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dokan Pro Admin',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => busy ? null : submit(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'Signing in…' : 'Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AdminHome extends StatefulWidget {
  const AdminHome({
    super.key,
    required this.gateway,
    required this.email,
    required this.onSignOut,
    this.photoPicker = const GalleryProductImagePicker(),
    this.preparePhoto = prepareCatalogPhoto,
  });
  final AdminGateway gateway;
  final String email;
  final VoidCallback onSignOut;
  final ProductImagePicker photoPicker;
  final CatalogPhotoPreparer preparePhoto;
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dokan Pro Admin'),
      actions: [
        Center(child: Text(widget.email)),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: widget.onSignOut,
        ),
      ],
    ),
    body: Row(
      children: [
        NavigationRail(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.store_outlined),
              label: Text('Shops'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.inventory_2_outlined),
              label: Text('Catalog'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.history),
              label: Text('Audit log'),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: switch (tab) {
            0 => ShopsPage(gateway: widget.gateway),
            1 => CatalogPage(
              gateway: widget.gateway,
              photoPicker: widget.photoPicker,
              preparePhoto: widget.preparePhoto,
            ),
            _ => AuditPage(gateway: widget.gateway),
          },
        ),
      ],
    ),
  );
}

Color _statusColor(BuildContext context, String status) {
  final s = Theme.of(context).colorScheme;
  return switch (status) {
    'active' || 'approved' => Colors.green.shade700,
    'pending' => Colors.orange.shade800,
    _ => s.error,
  };
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: _statusColor(context, label)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(color: _statusColor(context, label), fontSize: 12),
    ),
  );
}

class ShopsPage extends StatefulWidget {
  const ShopsPage({super.key, required this.gateway});
  final AdminGateway gateway;
  @override
  State<ShopsPage> createState() => _ShopsPageState();
}

class _ShopsPageState extends State<ShopsPage> {
  late Future<List<AdminShop>> shops = widget.gateway.shops();
  void reload() => setState(() {
    shops = widget.gateway.shops();
  });

  Future<void> create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => CreateShopDialog(gateway: widget.gateway),
    );
    if (created == true) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: const Icon(Icons.add_business),
      label: const Text('New shop'),
    ),
    body: FutureBuilder(
      future: shops,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(adminErrorText(snap.error!)));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('No shops yet.'));
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = rows[i];
              return ListTile(
                title: Row(
                  children: [
                    Flexible(child: Text(s.name)),
                    const SizedBox(width: 8),
                    _Chip(s.licenseStatus),
                    if (s.pendingDevices > 0) ...[
                      const SizedBox(width: 8),
                      Badge(
                        label: Text('${s.pendingDevices}'),
                        child: const Icon(Icons.devices_other, size: 20),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  '${s.ownerEmails.isEmpty ? 'No owner' : s.ownerEmails.join(', ')}'
                  ' · ${s.planId ?? '—'} until ${_date(s.periodEnd)}'
                  ' · ${s.approvedDevices}/2 devices',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ShopDetailPage(gateway: widget.gateway, shop: s),
                    ),
                  );
                  reload();
                },
              );
            },
          ),
        );
      },
    ),
  );
}

class CreateShopDialog extends StatefulWidget {
  const CreateShopDialog({super.key, required this.gateway});
  final AdminGateway gateway;
  @override
  State<CreateShopDialog> createState() => _CreateShopDialogState();
}

class _CreateShopDialogState extends State<CreateShopDialog> {
  final name = TextEditingController(),
      phone = TextEditingController(),
      address = TextEditingController(),
      ownerEmail = TextEditingController(),
      ownerName = TextEditingController(),
      password = TextEditingController();
  bool newLogin = true, busy = false;
  String? error;

  Future<void> submit() async {
    if (name.text.trim().isEmpty || ownerEmail.text.trim().isEmpty) {
      setState(() => error = 'Shop name and owner email are required.');
      return;
    }
    if (newLogin && password.text.length < 10) {
      setState(
        () => error = 'Temporary password needs at least 10 characters.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (newLogin) {
        await widget.gateway.createOwnerLogin(
          email: ownerEmail.text.trim(),
          temporaryPassword: password.text,
          fullName: ownerName.text.trim(),
        );
      }
      await widget.gateway.createShop(
        name: name.text.trim(),
        phone: phone.text.trim(),
        address: address.text.trim(),
        ownerEmail: ownerEmail.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = adminErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New shop'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            TextField(
              controller: ownerEmail,
              decoration: const InputDecoration(labelText: 'Owner email'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: newLogin,
              onChanged: (v) => setState(() => newLogin = v),
              title: const Text('Create a new owner login'),
              subtitle: const Text('Off: link an existing account'),
            ),
            if (newLogin) ...[
              TextField(
                controller: ownerName,
                decoration: const InputDecoration(labelText: 'Owner name'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary password (give to owner)',
                ),
              ),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'The shop starts pending. Activate and renew it after payment.',
              ),
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
        onPressed: busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(busy ? 'Creating…' : 'Create shop'),
      ),
    ],
  );
}

class ShopDetailPage extends StatefulWidget {
  const ShopDetailPage({super.key, required this.gateway, required this.shop});
  final AdminGateway gateway;
  final AdminShop shop;
  @override
  State<ShopDetailPage> createState() => _ShopDetailPageState();
}

class _ShopDetailPageState extends State<ShopDetailPage> {
  late AdminShop shop = widget.shop;
  late Future<List<AdminDevice>> devices = widget.gateway.devices(shop.id);
  late Future<List<AdminPlan>> plans = widget.gateway.plans();

  Future<void> reload() async {
    final all = await widget.gateway.shops();
    if (!mounted) return;
    setState(() {
      shop = all.firstWhere((s) => s.id == shop.id, orElse: () => shop);
      devices = widget.gateway.devices(shop.id);
    });
  }

  Future<String?> _ask(String title, {String label = 'Note'}) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> setStatus(String status) async {
    final note = await _ask(
      status == 'active' ? 'Activate shop' : 'Suspend shop',
    );
    if (note == null || !mounted) return;
    if (await _run(
      context,
      () => widget.gateway.setShopStatus(shop.id, status, note),
      status == 'active' ? 'Shop activated' : 'Shop suspended',
    )) {
      await reload();
    }
  }

  Future<void> renew(List<AdminPlan> paid) async {
    var plan = paid.first.id;
    var months = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Renew subscription'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: plan,
                decoration: const InputDecoration(labelText: 'Plan'),
                items: [
                  for (final p in paid)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.name} (${p.billingCycle})'),
                    ),
                ],
                onChanged: (v) => set(() => plan = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: months,
                decoration: const InputDecoration(labelText: 'Months'),
                items: [
                  for (final m in const [1, 3, 6, 12, 24])
                    DropdownMenuItem(value: m, child: Text('$m')),
                ],
                onChanged: (v) => set(() => months = v!),
              ),
              const SizedBox(height: 8),
              Text('Extends from ${_date(shop.periodEnd)} or today.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Renew'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (await _run(
      context,
      () => widget.gateway.renew(shop.id, plan, months),
      'Subscription renewed',
    )) {
      await reload();
    }
  }

  Future<void> approve(AdminDevice d, List<AdminDevice> all) async {
    final approved = all.where((x) => x.approvalStatus == 'approved').toList();
    String? replace;
    var form = d.formFactor;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text('Approve ${d.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: form,
                decoration: const InputDecoration(labelText: 'Slot'),
                items: const [
                  DropdownMenuItem(value: 'mobile', child: Text('Mobile')),
                  DropdownMenuItem(value: 'tablet', child: Text('Tablet')),
                ],
                onChanged: (v) => set(() => form = v!),
              ),
              DropdownButtonFormField<String?>(
                initialValue: replace,
                decoration: const InputDecoration(
                  labelText: 'Replace (revokes that device)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final a in approved)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} · ${deviceCode(a.id)} (${a.formFactor})'
                        ' · seen ${_date(a.lastSeenAt)}',
                      ),
                    ),
                ],
                onChanged: (v) => set(() => replace = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (await _run(
      context,
      () => widget.gateway.approveDevice(
        d.id,
        replaceDeviceId: replace,
        formFactor: form,
      ),
      replace == null ? 'Device approved' : 'Device replaced',
    )) {
      await reload();
    }
  }

  Future<void> reject(AdminDevice d) async {
    final note = await _ask('Reject ${d.name}');
    if (note == null || !mounted) return;
    if (await _run(
      context,
      () => widget.gateway.rejectDevice(d.id, note),
      'Device rejected',
    )) {
      await reload();
    }
  }

  Future<void> revoke(AdminDevice d) async {
    final note = await _ask('Revoke ${d.name}? It stops billing.');
    if (note == null || !mounted) return;
    if (await _run(
      context,
      () => widget.gateway.revokeDevice(d.id, note),
      'Device revoked',
    )) {
      await reload();
    }
  }

  Future<void> assignOwner() async {
    final email = await _ask('Assign owner', label: 'Owner email');
    if (email == null || email.isEmpty || !mounted) return;
    if (await _run(
      context,
      () => widget.gateway.assignOwner(shop.id, email),
      'Owner assigned',
    )) {
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(shop.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Licence', style: text.titleMedium),
                      const SizedBox(width: 8),
                      _Chip(shop.licenseStatus),
                    ],
                  ),
                  if (shop.licenseNote.isNotEmpty) Text(shop.licenseNote),
                  const SizedBox(height: 8),
                  Text(
                    'Owner: ${shop.ownerEmails.isEmpty ? '—' : shop.ownerEmails.join(', ')}',
                  ),
                  Text('Phone: ${shop.phone}  ·  Address: ${shop.address}'),
                  Text(
                    'Plan: ${shop.planId ?? '—'} (${shop.subscriptionStatus ?? '—'})'
                    '  ·  Expires: ${_date(shop.periodEnd)}'
                    '  ·  Offline grace until: ${_date(shop.graceUntil)}',
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder(
                    future: plans,
                    builder: (context, snap) {
                      final paid = (snap.data ?? const <AdminPlan>[])
                          .where((p) => p.billingCycle != 'trial')
                          .toList();
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (shop.licenseStatus != 'active')
                            FilledButton.icon(
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () => setStatus('active'),
                              label: const Text('Activate'),
                            ),
                          if (shop.licenseStatus != 'suspended')
                            OutlinedButton.icon(
                              icon: const Icon(Icons.block),
                              onPressed: () => setStatus('suspended'),
                              label: const Text('Suspend'),
                            ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.autorenew),
                            onPressed: paid.isEmpty ? null : () => renew(paid),
                            label: const Text('Renew'),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.person_add_alt),
                            onPressed: assignOwner,
                            label: const Text('Assign owner'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Devices (max 1 mobile + 1 tablet)', style: text.titleMedium),
          FutureBuilder(
            future: devices,
            builder: (context, snap) {
              if (snap.hasError) return Text(adminErrorText(snap.error!));
              if (!snap.hasData) return const LinearProgressIndicator();
              final all = snap.data!;
              if (all.isEmpty) return const Text('No devices yet.');
              return Column(
                children: [
                  for (final d in all)
                    ListTile(
                      leading: Icon(
                        d.formFactor == 'mobile'
                            ? Icons.smartphone
                            : Icons.tablet_android,
                      ),
                      title: Row(
                        children: [
                          Flexible(child: Text(d.name)),
                          const SizedBox(width: 8),
                          _Chip(d.approvalStatus),
                          if (d.legacy) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'legacy',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        'Code ${deviceCode(d.id)} · ${d.formFactor}'
                        ' · ${d.deviceType}'
                        ' · ${d.isActive ? 'on' : 'off'}'
                        ' · registered ${_date(d.createdAt)}'
                        ' · last seen ${_date(d.lastSeenAt)}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          if (d.approvalStatus != 'approved')
                            TextButton(
                              onPressed: () => approve(d, all),
                              child: const Text('Approve'),
                            ),
                          if (d.approvalStatus == 'pending')
                            TextButton(
                              onPressed: () => reject(d),
                              child: const Text('Reject'),
                            ),
                          if (d.approvalStatus == 'approved')
                            TextButton(
                              onPressed: () => revoke(d),
                              child: const Text('Revoke'),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Audit', style: text.titleMedium),
          SizedBox(
            height: 320,
            child: AuditPage(gateway: widget.gateway, shopId: shop.id),
          ),
        ],
      ),
    );
  }
}

class AuditPage extends StatelessWidget {
  const AuditPage({super.key, required this.gateway, this.shopId});
  final AdminGateway gateway;
  final String? shopId;
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: gateway.audit(shopId: shopId),
    builder: (context, snap) {
      if (snap.hasError) {
        return Center(child: Text(adminErrorText(snap.error!)));
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snap.data!;
      if (rows.isEmpty) return const Center(child: Text('No entries.'));
      return ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final e = rows[i];
          return ListTile(
            dense: true,
            title: Text(
              '${e.action}${e.shopName == null ? '' : ' · ${e.shopName}'}',
            ),
            subtitle: Text(
              '${_dateTime(e.createdAt)} · ${e.actorKind}'
              '${e.actorEmail == null ? '' : ' ${e.actorEmail}'}'
              '${e.details.isEmpty ? '' : ' · ${e.details}'}',
            ),
          );
        },
      );
    },
  );
}

/// Small square preview of a catalog photo: the processed JPEG about to be
/// uploaded, else the stored key from the public bucket, else a placeholder.
class _CatalogThumb extends StatelessWidget {
  const _CatalogThumb({this.path, this.bytes, this.size = 40});
  final String? path;
  final Uint8List? bytes;
  final double size;
  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(
      Icons.image_not_supported_outlined,
      size: size * 0.6,
    );
    final url = productImageUrl(path);
    final Widget image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover)
        : url != null
        ? Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          )
        : placeholder;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Center(child: image),
      ),
    );
  }
}

/// The global product catalog every shop browses (public.master_products).
/// Writes go through admin_upsert_master_product and
/// admin_set_master_product_image (migration 202610180002).
class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.gateway,
    this.photoPicker = const GalleryProductImagePicker(),
    this.preparePhoto = prepareCatalogPhoto,
  });
  final AdminGateway gateway;
  final ProductImagePicker photoPicker;
  final CatalogPhotoPreparer preparePhoto;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final search = TextEditingController();
  late Future<List<AdminCatalogProduct>> products = widget.gateway
      .catalogProducts();
  late Future<List<AdminCategory>> categories = widget.gateway
      .catalogCategories();

  void reload() => setState(() {
    products = widget.gateway.catalogProducts(query: search.text);
  });

  Future<void> edit([AdminCatalogProduct? product]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogProductDialog(
        gateway: widget.gateway,
        categories: categories,
        product: product,
        photoPicker: widget.photoPicker,
        preparePhoto: widget.preparePhoto,
      ),
    );
    if (saved == true) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: edit,
      icon: const Icon(Icons.add),
      label: const Text('New product'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              labelText: 'Search name, brand or barcode',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward),
                onPressed: reload,
              ),
            ),
            onSubmitted: (_) => reload(),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: products,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text(adminErrorText(snap.error!)));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return const Center(child: Text('No catalog products.'));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = rows[i];
                  return ListTile(
                    leading: _CatalogThumb(path: p.imagePath),
                    title: Row(
                      children: [
                        Flexible(child: Text(p.name)),
                        if (!p.isActive) ...[
                          const SizedBox(width: 8),
                          const _Chip('hidden'),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      [
                        p.barcode,
                        if (p.brand.isNotEmpty) p.brand,
                        p.defaultUnit,
                        if (p.packLabel case final String pack) pack,
                        if (p.imagePath == null) 'no photo',
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => edit(p),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// Creates or edits one catalog product and its photo. The row is saved
/// first; a picked photo (already shrunk to the 512px JPEG) is then uploaded
/// under its content hash and attached. If the photo step fails the row
/// stays saved and the dialog stays open to retry it.
class CatalogProductDialog extends StatefulWidget {
  const CatalogProductDialog({
    super.key,
    required this.gateway,
    required this.categories,
    this.product,
    this.photoPicker = const GalleryProductImagePicker(),
    this.preparePhoto = prepareCatalogPhoto,
  });
  final AdminGateway gateway;
  final Future<List<AdminCategory>> categories;
  final AdminCatalogProduct? product;
  final ProductImagePicker photoPicker;
  final CatalogPhotoPreparer preparePhoto;
  @override
  State<CatalogProductDialog> createState() => _CatalogProductDialogState();
}

class _CatalogProductDialogState extends State<CatalogProductDialog> {
  late final AdminCatalogProduct? initial = widget.product;
  late final name = TextEditingController(text: initial?.name);
  late final brand = TextEditingController(text: initial?.brand);
  late final barcode = TextEditingController(text: initial?.barcode);
  late final pack = TextEditingController(text: initial?.packLabel);
  late String? categoryId = initial?.categoryId;
  late String unit = initial?.defaultUnit ?? ProductUnit.piece.name;
  late bool active = initial?.isActive ?? true;
  late String? savedId = initial?.id;

  /// The processed JPEG waiting to be uploaded on save.
  Uint8List? newPhoto;
  bool removePhoto = false, busy = false, changed = false;
  String? error;

  Future<void> pickPhoto() async {
    setState(() => error = null);
    try {
      final picked = await widget.photoPicker.pick();
      if (picked == null) return;
      setState(() => busy = true);
      final jpeg = await widget.preparePhoto(picked);
      if (mounted) {
        setState(() {
          newPhoto = jpeg;
          removePhoto = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = adminErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || barcode.text.trim().isEmpty) {
      setState(() => error = 'Name and barcode are required.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await widget.gateway.saveCatalogProduct(
        AdminCatalogProduct(
          id: savedId,
          name: name.text.trim(),
          brand: brand.text.trim(),
          barcode: barcode.text.trim(),
          categoryId: categoryId,
          defaultUnit: unit,
          packLabel: pack.text.trim().isEmpty ? null : pack.text.trim(),
          isActive: active,
        ),
      );
      savedId = id;
      changed = true;
      try {
        final photo = newPhoto;
        if (photo != null) {
          await attachCatalogPhoto(widget.gateway, id, photo);
        } else if (removePhoto && initial?.imagePath != null) {
          await widget.gateway.setCatalogImage(id, null);
        }
      } catch (e) {
        if (mounted) {
          setState(
            () => error =
                'Product saved, but the photo was not: ${adminErrorText(e)}',
          );
        }
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = adminErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = [
      for (final u in ProductUnit.values) u.name,
      // Older rows may use a unit the form no longer offers ('unit').
      if (!ProductUnit.values.any((u) => u.name == unit)) unit,
    ];
    final hasPhoto =
        newPhoto != null || (!removePhoto && initial?.imagePath != null);
    return AlertDialog(
      title: Text(
        initial == null ? 'New catalog product' : 'Edit catalog product',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: brand,
                decoration: const InputDecoration(labelText: 'Brand'),
              ),
              TextField(
                controller: barcode,
                decoration: const InputDecoration(labelText: 'Barcode'),
              ),
              FutureBuilder(
                future: widget.categories,
                builder: (context, snap) {
                  final all = snap.data ?? const <AdminCategory>[];
                  return DropdownButtonFormField<String?>(
                    key: ValueKey(all.length),
                    initialValue: all.any((c) => c.id == categoryId)
                        ? categoryId
                        : null,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final c in all)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => categoryId = v),
                  );
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Default unit'),
                items: [
                  for (final u in units)
                    DropdownMenuItem(value: u, child: Text(u)),
                ],
                onChanged: busy ? null : (v) => setState(() => unit = v!),
              ),
              TextField(
                controller: pack,
                decoration: const InputDecoration(
                  labelText: 'Pack label (e.g. 200 g)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                onChanged: busy ? null : (v) => setState(() => active = v),
                title: const Text('Shown in shop catalog'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _CatalogThumb(
                    path: removePhoto ? null : initial?.imagePath,
                    bytes: newPhoto,
                    size: 72,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.photo_outlined),
                          onPressed: busy ? null : pickPhoto,
                          label: Text(hasPhoto ? 'Change photo' : 'Add photo'),
                        ),
                        if (hasPhoto)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    newPhoto = null;
                                    removePhoto = true;
                                  }),
                            child: const Text('Remove photo'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(changed),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
