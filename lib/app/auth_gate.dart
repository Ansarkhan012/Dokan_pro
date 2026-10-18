import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/l10n/language_switcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_repository.dart';
import '../auth/supabase_auth_repository.dart';
import '../auth/auth_session_controller.dart';
import '../auth/cashier_session.dart';
import '../auth/cashier_session_manager.dart';
import '../auth/cashier_session_store.dart';
import '../auth/device_credential.dart';
import '../auth/device_mode.dart';
import '../auth/owner_mode_lock.dart';
import '../auth/supabase_cashier_auth_gateway.dart';
import '../core/device/app_device_id.dart';
import 'device_approval_notice.dart';
import '../core/device/preferences_device_id_store.dart';
import '../core/errors/safe_error_message.dart';
import '../core/domain/enums.dart';
import '../core/ids/id_generator.dart';
import '../subscription/activation_status.dart';
import '../subscription/entitlement_store.dart';
import '../subscription/entitlement_verifier.dart';
import '../subscription/supabase_entitlement_gateway.dart';
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
import '../features/sync/sync_attention.dart';
import 'cashier_login_panel.dart';
import 'cashier_resume_gate.dart';
import 'device_mode_scope.dart';
import 'owner_sync_resume.dart';
import 'owner_access.dart';
import '../core/l10n/l10n.dart';
import '../core/l10n/messages.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.client,
    required this.ownerSessionStorage,
  });
  final SupabaseClient client;
  final LocalStorage ownerSessionStorage;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final auth = SupabaseAuthRepository(widget.client);
  late final session = AuthSessionController(auth)..start();
  final ownerLock = OwnerModeLock(SecureOwnerModeLockStore())..load();
  final deviceReload = ValueNotifier(0);
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
    // Signing back in needs the owner password, so the lock is no longer needed.
    await ownerLock.release();
    // A provisioned device returns to its cashier lobby.
    deviceReload.value++;
  }

  @override
  void dispose() {
    session.dispose();
    ownerLock.dispose();
    deviceReload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CashierResumeGate(
    client: widget.client,
    ownerSessionStorage: widget.ownerSessionStorage,
    reloadSignal: deviceReload,
    child: StreamBuilder<AuthSessionState>(
      stream: session.states,
      initialData: session.state,
      builder: (context, snapshot) => snapshot.data?.userId == null
          ? AuthForm(auth: auth, session: session, ownerLock: ownerLock)
          : OwnerBootstrap(
              client: widget.client,
              session: session,
              ownerLock: ownerLock,
              onSignOut: signOut,
            ),
    ),
  );
}

class AuthForm extends StatefulWidget {
  const AuthForm({
    super.key,
    required this.auth,
    required this.session,
    required this.ownerLock,
  });
  final AuthRepository auth;
  final AuthSessionController session;
  final OwnerModeLock ownerLock;
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool submitting = false;

  /// Resolved when shown, so a language switch also translates the error.
  String Function(AppLocalizations)? error;
  String Function(AppLocalizations)? notice;
  Future<void> submit() async {
    if (submitting) return;
    setState(() {
      submitting = true;
      error = null;
      notice = null;
    });
    try {
      await widget.session.signIn(
        email: email.text.trim(),
        password: password.text,
      );
      // The owner just entered their password on this device.
      await widget.ownerLock.release();
    } on AuthException catch (e) {
      if (mounted) setState(() => error = _friendlyAuthError(e));
    } catch (_) {
      if (mounted) {
        setState(() => error = (l10n) => l10n.authErrSignInConnection);
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  /// The answer never says whether the email has an account.
  Future<void> resetPassword() async {
    if (submitting) return;
    final address = email.text.trim();
    if (address.isEmpty) {
      setState(() {
        notice = null;
        error = (l10n) => l10n.authResetNeedsEmail;
      });
      return;
    }
    setState(() {
      submitting = true;
      error = null;
      notice = null;
    });
    try {
      await widget.auth.sendPasswordReset(email: address);
      if (mounted) setState(() => notice = (l10n) => l10n.authResetSent);
    } on AuthException catch (e) {
      final message = e.message.toLowerCase();
      final offline =
          message.contains('network') || message.contains('connection');
      if (mounted) {
        setState(() {
          if (offline) {
            error = (l10n) => l10n.authErrNoConnection;
          } else {
            notice = (l10n) => l10n.authResetSent;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = (l10n) => l10n.authErrNoConnection);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Page(
      title: l10n.authOwnerSignIn,
      children: [
        // Email and password are always typed left to right.
        TextField(
          controller: email,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: l10n.authEmail),
        ),
        TextField(
          controller: password,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: l10n.authPassword),
        ),
        if (error case final error?)
          Text(
            error(l10n),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (notice case final notice?) Text(notice(l10n)),
        FilledButton(
          onPressed: submitting ? null : submit,
          child: Text(submitting ? l10n.authPleaseWait : l10n.authSignIn),
        ),
        TextButton(
          onPressed: submitting ? null : resetPassword,
          child: Text(l10n.authForgotPassword),
        ),
        // No self-registration: shops and owner accounts come from support.
        const ContactSupportNotice(),
      ],
    );
  }
}

/// Replaces every former sign-up and create-shop entry point.
class ContactSupportNotice extends StatelessWidget {
  const ContactSupportNotice({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.l10n.activationContactSupport,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      Text(
        context.l10n.activationSupportNote,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

/// Signed in, but the account has no shop: only support can provision one.
class NoShopPage extends StatelessWidget {
  const NoShopPage({super.key, required this.onSignOut});
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => _Page(
    title: context.l10n.activationNoShopTitle,
    children: [
      Text(context.l10n.activationNoShopBody),
      const ContactSupportNotice(),
      TextButton(onPressed: onSignOut, child: Text(context.l10n.commonSignOut)),
    ],
  );
}

class OwnerBootstrap extends StatefulWidget {
  const OwnerBootstrap({
    super.key,
    required this.client,
    required this.session,
    required this.ownerLock,
    required this.onSignOut,
  });
  final SupabaseClient client;
  final AuthSessionController session;
  final OwnerModeLock ownerLock;
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
          title: context.l10n.onboardLoadFailedTitle,
          children: [
            Text(context.l10n.onboardLoadFailed),
            TextButton(
              onPressed: widget.onSignOut,
              child: Text(context.l10n.commonSignOut),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return switch (snapshot.data!) {
        NoShopAssigned() => NoShopPage(onSignOut: widget.onSignOut),
        ShopReady(:final membership) => RegisterDevicePage(
          client: widget.client,
          session: widget.session,
          membership: membership,
          ownerLock: widget.ownerLock,
          onSignOut: widget.onSignOut,
        ),
      };
    },
  );
}

class RegisterDevicePage extends StatefulWidget {
  const RegisterDevicePage({
    super.key,
    required this.client,
    required this.session,
    required this.membership,
    required this.ownerLock,
    required this.onSignOut,
  });
  final SupabaseClient client;
  final AuthSessionController session;
  final ShopMembership membership;
  final OwnerModeLock ownerLock;
  final Future<void> Function() onSignOut;
  @override
  State<RegisterDevicePage> createState() => _RegisterDevicePageState();
}

class _RegisterDevicePageState extends State<RegisterDevicePage> {
  final name = TextEditingController(text: _defaultDeviceName);
  RegisteredDevice? device;
  ActivationStatus? activation;
  String? deviceIdentifier;

  /// Resolved when shown, so a language switch also translates the error.
  String Function(AppLocalizations)? error;
  CashierSession? cashierSession;
  String? cashierName;
  bool registering = false;
  bool restoringDevice = true;
  late final ownerReauthenticator = SupabaseOwnerReauthenticator(widget.client);
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
      unawaited(loadActivation(identifier));
      if (restored != null && restored.isActive) {
        // Reconnect: learn about suspension, revocation or renewal now. A
        // refusal is recorded locally and blocks billing; an outage is not.
        unawaited(_refreshEntitlement(restored.id));
        unawaited(
          resumeOwnerSync(
            ownerClient: widget.client,
            shopId: widget.membership.shopId,
            deviceId: restored.id,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          restoringDevice = false;
          error = (l10n) => l10n.deviceErrCheck;
        });
      }
    }
  }

  Future<void> loadActivation(String identifier) async {
    try {
      final value = await SupabaseActivationStatusGateway(
        widget.client,
      ).load(shopId: widget.membership.shopId, deviceIdentifier: identifier);
      if (mounted) setState(() => activation = value);
    } catch (_) {
      // Display only; offline billing never waits on this read.
    }
  }

  Future<void> register() async {
    if (registering) return;
    final type = _currentDeviceType(context);
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
      final result = await SupabaseDeviceRegistrationGateway(widget.client)
          .register(
            shopId: widget.membership.shopId,
            deviceName: name.text.trim(),
            type: type,
            identifier: identifier,
          );
      unawaited(loadActivation(identifier));
      if (mounted) {
        setState(() => device = result);
        widget.session.deviceResolved(
          registered: true,
          active: result.isActive,
        );
      }
    } catch (e) {
      if (mounted) {
        // English keeps the exact text safeUserMessage chose.
        final message = safeUserMessage(
          e,
          fallback: 'Could not register this device. Check your connection.',
        );
        setState(() => error = (l10n) => localizedMessage(l10n, message));
      }
    } finally {
      if (mounted) setState(() => registering = false);
    }
  }

  /// Hands the device to cashier mode. In order, and nothing cashier-facing
  /// opens unless every step succeeds:
  /// 1. the device credential exists (provisioning it needs a verified owner),
  /// 2. the subscription entitlement is refreshed while the owner can,
  /// 3. owner mode is locked (persisted),
  /// 4. the device gate removes the owner session, verifies no owner token
  ///    remains and opens the cashier session on the session-less client.
  Future<void> enterCashierMode(CashierSession session, String name) async {
    final scope = DeviceModeScope.maybeOf(context);
    if (scope == null) {
      // Web preview: no cashier runtime or sync, only the preview screen.
      setState(() {
        error = null;
        cashierSession = session;
        cashierName = name;
      });
      return;
    }
    try {
      await DeviceModeService(
        owner: SupabaseOwnerAuthority(widget.client, const EmptyLocalStorage()),
        credentials: SecureDeviceCredentialStore(),
        cashierSessions: SecureCashierSessionStore(),
        lockStore: SecureOwnerModeLockStore(),
      ).ensureCredential(
        shopId: widget.membership.shopId,
        shopName: widget.membership.shopName,
        deviceId: device!.id,
        deviceIdentifier: deviceIdentifier!,
        ownerVerified: widget.ownerLock.ownerAccessAllowed,
        issuer: SupabaseDeviceCredentialIssuer(widget.client),
      );
    } on DeviceNotProvisioned {
      await _abandonCashierSession();
      _fail((l10n) => l10n.deviceErrCashierNeedsOwner);
      return;
    } catch (_) {
      await _abandonCashierSession();
      _fail((l10n) => l10n.deviceErrCashierSetup);
      return;
    }
    await _refreshEntitlement(session.deviceId);
    try {
      await widget.ownerLock.engage();
    } catch (_) {
      await _abandonCashierSession();
      _fail((l10n) => l10n.deviceErrSecureOwner);
      return;
    }
    if (!mounted) return;
    widget.session.cashierResolved(offline: false);
    scope.startCashierMode(name);
  }

  Future<void> _refreshEntitlement(String deviceId) async {
    try {
      await SupabaseEntitlementGateway(
            widget.client,
            EntitlementVerifier(rsaPublicKeyFromEnvironment()),
            SecureEntitlementStore(),
          )
          .refresh(
            shopId: widget.membership.shopId,
            deviceId: deviceId,
            localNow: DateTime.now(),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // A cached entitlement stays authoritative; cashier mode re-checks it.
    }
  }

  Future<void> _abandonCashierSession() async {
    try {
      await CashierSessionManager(
        SupabaseCashierAuthGateway(widget.client),
        SecureCashierSessionStore(),
      ).logout();
    } catch (_) {}
  }

  void _fail(String Function(AppLocalizations) message) {
    if (mounted) setState(() => error = message);
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
        if (activation case final activation?)
          ActivationStatusPanel(status: activation),
        if (restoringDevice)
          const Center(child: CircularProgressIndicator())
        else if (device == null) ...[
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: context.l10n.deviceName),
          ),
          FilledButton(
            onPressed: registering ? null : register,
            child: Text(
              registering
                  ? context.l10n.deviceRegistering
                  : context.l10n.deviceRegister,
            ),
          ),
        ] else if (device!.awaitingApproval)
          DeviceApprovalPendingNotice(
            deviceId: device!.id,
            onCheckAgain: () {
              setState(() => restoringDevice = true);
              restoreDevice();
            },
          )
        else if (device!.rejected)
          Text(context.l10n.deviceApprovalRejected)
        else if (!device!.isActive)
          Text(context.l10n.deviceRevoked)
        else ...[
          Text(context.l10n.deviceActive),
          OwnerModeSection(
            lock: widget.ownerLock,
            reauthenticator: ownerReauthenticator,
            actions: [
              OwnerAction(
                label: context.l10n.ownerNavDashboard,
                icon: Icons.analytics_outlined,
                primary: true,
                builder: (_) => OwnerDashboardScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  shopName: widget.membership.shopName,
                ),
              ),
              OwnerAction(
                label: context.l10n.ownerNavSettings,
                icon: Icons.settings_outlined,
                builder: (_) => OwnerSettingsScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
              OwnerAction(
                label: context.l10n.ownerNavSalesReturns,
                icon: Icons.receipt_long_outlined,
                builder: (_) => SalesManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  shopName: widget.membership.shopName,
                  deviceId: device!.id,
                ),
              ),
              OwnerAction(
                label: context.l10n.ownerNavInventory,
                icon: Icons.warehouse_outlined,
                builder: (_) => InventoryManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
              OwnerAction(
                label: context.l10n.ownerNavProducts,
                icon: Icons.inventory_2_outlined,
                builder: (_) => ProductManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
              OwnerAction(
                label: context.l10n.ownerNavCustomers,
                icon: Icons.people_outline,
                builder: (_) => CustomerManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
              OwnerAction(
                label: context.l10n.ownerNavPurchases,
                icon: Icons.local_shipping_outlined,
                builder: (_) => PurchaseManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
              OwnerAction(
                label: context.l10n.ownerNavExpenses,
                icon: Icons.payments_outlined,
                builder: (_) => ExpenseManagementScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
              OwnerAction(
                label: context.l10n.syncIssuesTitle,
                icon: Icons.sync_problem_outlined,
                builder: (_) => SyncAttentionScreen(
                  client: widget.client,
                  shopId: widget.membership.shopId,
                  deviceId: device!.id,
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: widget.ownerLock,
            builder: (context, _) => CashierLoginPanel(
              client: widget.client,
              shopId: widget.membership.shopId,
              shopName: widget.membership.shopName,
              deviceIdentifier: deviceIdentifier!,
              allowManagement: widget.ownerLock.ownerAccessAllowed,
              onAuthenticated: enterCashierMode,
            ),
          ),
        ],
        if (error case final error?) Text(error(context.l10n)),
        TextButton(
          onPressed: widget.onSignOut,
          child: Text(context.l10n.commonSignOut),
        ),
      ],
    );
  }
}

/// The sign-in error to show; the server's own text is never shown.
String Function(AppLocalizations) _friendlyAuthError(AuthException error) {
  final message = error.message.toLowerCase();
  if (message.contains('invalid login') ||
      message.contains('invalid credentials')) {
    return (l10n) => l10n.authErrWrongCredentials;
  }
  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('connection')) {
    return (l10n) => l10n.authErrNoConnection;
  }
  if (message.contains('expired') || message.contains('refresh token')) {
    return (l10n) => l10n.authErrSessionExpired;
  }
  return (l10n) => l10n.authErrSignInDetails;
}

/// Shortest side of the first window in logical pixels, without a context.
double get _shortestSide {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 0;
  final view = views.first;
  return (view.physicalSize / view.devicePixelRatio).shortestSide;
}

String get _defaultDeviceName {
  if (kIsWeb) return 'Web preview';
  return switch (classifyDeviceType(
    isWeb: false,
    platform: defaultTargetPlatform,
    shortestSide: _shortestSide,
  )) {
    DeviceType.windowsDesktop => 'Windows counter',
    DeviceType.androidTablet => 'Android tablet',
    _ => 'Owner mobile',
  };
}

DeviceType _currentDeviceType(BuildContext context) => classifyDeviceType(
  isWeb: kIsWeb,
  platform: defaultTargetPlatform,
  shortestSide: MediaQuery.sizeOf(context).shortestSide,
);

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: const [LanguageSwitcher()]),
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
