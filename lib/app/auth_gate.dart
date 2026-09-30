import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/supabase_auth_repository.dart';
import '../auth/auth_session_controller.dart';
import '../auth/cashier_session.dart';
import '../auth/cashier_session_manager.dart';
import '../auth/cashier_session_store.dart';
import '../auth/supabase_cashier_auth_gateway.dart';
import '../core/device/app_device_id.dart';
import '../core/device/preferences_device_id_store.dart';
import '../core/errors/safe_error_message.dart';
import '../core/domain/enums.dart';
import '../core/ids/id_generator.dart';
import '../features/shop/device_registration_gateway.dart';
import '../features/shop/domain/shop_membership.dart';
import '../features/shop/shop_bootstrap_gateway.dart';
import '../features/shop/shop_bootstrap_service.dart';
import '../features/shop/supabase_device_registration_gateway.dart';
import '../features/shop/supabase_shop_bootstrap_gateway.dart';
import '../features/pos/pos_runtime.dart';
import '../features/products/product_management.dart';
import '../features/customers/customer_management.dart';
import '../features/purchases/purchase_management.dart';
import '../features/expenses/expense_management.dart';
import '../features/reports/owner_dashboard.dart';
import '../features/sales/sales_management.dart';
import '../features/inventory/inventory_management.dart';
import '../features/settings/owner_settings_screen.dart';
import 'cashier_login_panel.dart';
import 'cashier_resume_gate.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final auth = SupabaseAuthRepository(widget.client);
  late final session = AuthSessionController(auth)..start();
  Future<void> signOut() async {
    try {
      await CashierSessionManager(
        SupabaseCashierAuthGateway(widget.client),
        SecureCashierSessionStore(),
      ).logout();
    } catch (_) {
      // Local cashier credentials are cleared even when server revocation is
      // unavailable. Supabase sign-out still needs to run.
    }
    await session.signOut();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CashierResumeGate(
    client: widget.client,
    child: StreamBuilder<AuthSessionState>(
      stream: session.states,
      initialData: session.state,
      builder: (context, snapshot) => snapshot.data?.userId == null
          ? AuthForm(auth: auth, session: session)
          : OwnerBootstrap(
              client: widget.client,
              session: session,
              onSignOut: signOut,
            ),
    ),
  );
}

class AuthForm extends StatefulWidget {
  const AuthForm({super.key, required this.auth, required this.session});
  final SupabaseAuthRepository auth;
  final AuthSessionController session;
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool signUp = false;
  bool submitting = false;
  String? error;
  Future<void> submit() async {
    if (submitting) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      if (signUp) {
        await widget.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          fullName: name.text.trim(),
        );
      } else {
        await widget.session.signIn(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = _friendlyAuthError(e));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Could not sign in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: signUp ? 'Create owner account' : 'Owner sign in',
    children: [
      if (signUp)
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      FilledButton(
        onPressed: submitting ? null : submit,
        child: Text(
          submitting
              ? 'Please wait…'
              : signUp
              ? 'Sign up'
              : 'Sign in',
        ),
      ),
      TextButton(
        onPressed: () => setState(() => signUp = !signUp),
        child: Text(
          signUp ? 'Have an account? Sign in' : 'Create owner account',
        ),
      ),
    ],
  );
}

class OwnerBootstrap extends StatefulWidget {
  const OwnerBootstrap({
    super.key,
    required this.client,
    required this.session,
    required this.onSignOut,
  });
  final SupabaseClient client;
  final AuthSessionController session;
  final Future<void> Function() onSignOut;
  @override
  State<OwnerBootstrap> createState() => _OwnerBootstrapState();
}

class _OwnerBootstrapState extends State<OwnerBootstrap> {
  late final ShopBootstrapGateway gateway = SupabaseShopBootstrapGateway(
    widget.client,
  );
  late Future<ShopBootstrapState> state = resolve();

  Future<ShopBootstrapState> resolve() async {
    final result = await ShopBootstrapService(gateway).resolve();
    if (mounted && result is ShopReady) {
      widget.session.ownerResolved(active: true);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: state,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _Page(
          title: 'Bootstrap failed',
          children: [
            const Text(
              'Could not load your shop. Check your connection and try again.',
            ),
            TextButton(
              onPressed: widget.onSignOut,
              child: const Text('Sign out'),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return switch (snapshot.data!) {
        NeedsShopCreation() => CreateShopForm(
          gateway: gateway,
          onCreated: (shop) {
            setState(() {
              state = Future.value(ShopReady(shop));
            });
            widget.session.ownerResolved(active: true);
          },
        ),
        ShopReady(:final membership) => RegisterDevicePage(
          client: widget.client,
          session: widget.session,
          membership: membership,
          onSignOut: widget.onSignOut,
        ),
      };
    },
  );
}

class CreateShopForm extends StatefulWidget {
  const CreateShopForm({
    super.key,
    required this.gateway,
    required this.onCreated,
  });
  final ShopBootstrapGateway gateway;
  final ValueChanged<ShopMembership> onCreated;
  @override
  State<CreateShopForm> createState() => _CreateShopFormState();
}

class _CreateShopFormState extends State<CreateShopForm> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  String? error;
  bool isSubmitting = false;

  Future<void> create() async {
    if (isSubmitting) return;

    setState(() {
      isSubmitting = true;
      error = null;
    });

    try {
      final shop = await widget.gateway.createOwnerShop(
        name: name.text.trim(),
        phone: phone.text.trim(),
        address: address.text.trim(),
      );

      if (!mounted) return;
      widget.onCreated(shop);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isSubmitting = false;
        error = 'Could not create your shop. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Create your shop',
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
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      FilledButton(
        onPressed: isSubmitting ? null : create,
        child: Text(isSubmitting ? 'Creating shop…' : 'Create shop'),
      ),
    ],
  );
}

class RegisterDevicePage extends StatefulWidget {
  const RegisterDevicePage({
    super.key,
    required this.client,
    required this.session,
    required this.membership,
    required this.onSignOut,
  });
  final SupabaseClient client;
  final AuthSessionController session;
  final ShopMembership membership;
  final Future<void> Function() onSignOut;
  @override
  State<RegisterDevicePage> createState() => _RegisterDevicePageState();
}

class _RegisterDevicePageState extends State<RegisterDevicePage> {
  final name = TextEditingController(text: _defaultDeviceName);
  RegisteredDevice? device;
  String? deviceIdentifier;
  String? error;
  CashierSession? cashierSession;
  String? cashierName;
  bool registering = false;
  bool restoringDevice = true;
  @override
  void initState() {
    super.initState();
    restoreDevice();
  }

  Future<void> restoreDevice() async {
    try {
      final identifier = await AppDeviceIdProvider(
        PreferencesDeviceIdStore(),
        const UuidV7Generator(),
      ).getOrCreate();
      final restored = await SupabaseDeviceRegistrationGateway(
        widget.client,
      ).find(shopId: widget.membership.shopId, identifier: identifier);
      if (!mounted) return;
      setState(() {
        deviceIdentifier = identifier;
        device = restored;
        restoringDevice = false;
      });
      widget.session.deviceResolved(
        registered: restored != null,
        active: restored?.isActive ?? false,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          restoringDevice = false;
          error =
              'Could not check this device registration. Check your connection.';
        });
      }
    }
  }

  Future<void> register() async {
    if (registering) return;
    setState(() {
      registering = true;
      error = null;
    });
    try {
      final identifier = await AppDeviceIdProvider(
        PreferencesDeviceIdStore(),
        const UuidV7Generator(),
      ).getOrCreate();
      deviceIdentifier = identifier;
      final type = _currentDeviceType;
      final result = await SupabaseDeviceRegistrationGateway(widget.client)
          .register(
            shopId: widget.membership.shopId,
            deviceName: name.text.trim(),
            type: type,
            identifier: identifier,
          );
      if (mounted) {
        setState(() => device = result);
        widget.session.deviceResolved(
          registered: true,
          active: result.isActive,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = safeUserMessage(
            e,
            fallback: 'Could not register this device. Check your connection.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => registering = false);
    }
  }

  Future<void> exitCashier() async {
    try {
      await CashierSessionManager(
        SupabaseCashierAuthGateway(widget.client),
        SecureCashierSessionStore(),
      ).logout();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      cashierSession = null;
      cashierName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = cashierSession;
    if (session != null) {
      return PosRuntime(
        client: widget.client,
        shopId: widget.membership.shopId,
        shopName: widget.membership.shopName,
        cashierId: session.cashierId,
        cashierName: cashierName!,
        deviceId: session.deviceId,
        onExit: exitCashier,
      );
    }
    return _Page(
      title: widget.membership.shopName,
      children: [
        if (restoringDevice)
          const Center(child: CircularProgressIndicator())
        else if (device == null) ...[
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Device name'),
          ),
          FilledButton(
            onPressed: registering ? null : register,
            child: Text(registering ? 'Registering…' : 'Register this device'),
          ),
        ] else if (!device!.isActive)
          const Text('Device is revoked.')
        else ...[
          const Text('Device active. Local sales foundation is ready.'),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OwnerDashboardScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  shopName: widget.membership.shopName,
                ),
              ),
            ),
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('Owner Dashboard'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OwnerSettingsScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Settings'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SalesManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  shopName: widget.membership.shopName,
                  deviceId: device!.id,
                ),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Sales & Returns'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InventoryManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
            ),
            icon: const Icon(Icons.warehouse_outlined),
            label: const Text('Inventory'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProductManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
            ),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Manage products'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CustomerManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
            ),
            icon: const Icon(Icons.people_outline),
            label: const Text('Manage customers / Khata'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PurchaseManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
            ),
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Suppliers & Purchases'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExpenseManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
            ),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Expenses'),
          ),
          CashierLoginPanel(
            client: widget.client,
            shopId: widget.membership.shopId,
            shopName: widget.membership.shopName,
            deviceIdentifier: deviceIdentifier!,
            onAuthenticated: (session, name) {
              setState(() {
                cashierSession = session;
                cashierName = name;
              });
              widget.session.cashierResolved(offline: false);
            },
          ),
        ],
        if (error != null) Text(error!),
        TextButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
      ],
    );
  }
}

String _friendlyAuthError(AuthException error) {
  final message = error.message.toLowerCase();
  if (message.contains('invalid login') ||
      message.contains('invalid credentials')) {
    return 'Wrong email or password.';
  }
  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection')) {
    return 'No connection to the server. Check your internet and try again.';
  }
  if (message.contains('expired') || message.contains('refresh token')) {
    return 'Your session expired. Please sign in again.';
  }
  return 'Could not sign in. Please check your details and try again.';
}

String get _defaultDeviceName {
  if (kIsWeb) return 'Web preview';
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'Windows counter',
    TargetPlatform.android => 'Android tablet',
    _ => 'Owner mobile',
  };
}

DeviceType get _currentDeviceType {
  if (kIsWeb) return DeviceType.mobile;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => DeviceType.windowsDesktop,
    TargetPlatform.android => DeviceType.androidTablet,
    _ => DeviceType.mobile,
  };
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: children
              .map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: w,
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
}
