import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/cashier_session.dart';
import '../auth/cashier_session_manager.dart';
import '../auth/cashier_session_store.dart';
import '../auth/device_credential.dart';
import '../auth/device_mode.dart';
import '../auth/owner_mode_lock.dart';
import '../auth/supabase_cashier_auth_gateway.dart';
import '../core/config/app_environment.dart';
import '../database/app_database.dart';
import '../features/pos/pos_runtime.dart';
import '../features/shop/device_cashier_directory.dart';
import '../core/device/app_device_id.dart';
import '../core/device/preferences_device_id_store.dart';
import '../core/ids/id_generator.dart';
import 'cashier_login_panel.dart';
import 'device_mode_scope.dart';

/// The owner/cashier boundary of this device.
///
/// Cashier mode runs only here, on a session-less client that carries the
/// device credential; the owner's Supabase session is removed (and verified
/// gone) before it opens, and a locked owner session found at startup is
/// removed the same way. Without an owner session the device shows the
/// cashier lobby, which works offline for a cached cashier session.
class CashierResumeGate extends StatefulWidget {
  const CashierResumeGate({
    super.key,
    required this.client,
    required this.ownerSessionStorage,
    required this.reloadSignal,
    required this.child,
  });

  final SupabaseClient client;
  final LocalStorage ownerSessionStorage;

  /// Fires after a full owner sign-out so the device state is read again.
  final Listenable reloadSignal;
  final Widget child;

  @override
  State<CashierResumeGate> createState() => _CashierResumeGateState();
}

class _CashierResumeGateState extends State<CashierResumeGate> {
  late final service = DeviceModeService(
    owner: SupabaseOwnerAuthority(widget.client, widget.ownerSessionStorage),
    credentials: SecureDeviceCredentialStore(),
    cashierSessions: SecureCashierSessionStore(),
    lockStore: SecureOwnerModeLockStore(),
  );
  late Future<DeviceModeState> state = _resolve();
  bool ownerSignInRequested = false;
  String? cashierName;
  SupabaseClient? _deviceClient;
  DeviceCredential? _deviceClientCredential;

  @override
  void initState() {
    super.initState();
    widget.reloadSignal.addListener(_reload);
  }

  @override
  void dispose() {
    widget.reloadSignal.removeListener(_reload);
    _deviceClient?.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    ownerSignInRequested = false;
    state = _resolve();
  });

  /// A cashier just authenticated online: open cashier mode for it.
  void _startCashier(String name) => setState(() {
    ownerSignInRequested = false;
    cashierName = name;
    state = _resolve(sessionJustCreated: true);
  });

  Future<DeviceModeState> _resolve({bool sessionJustCreated = false}) async {
    final resolved = await service.resolve(
      hasLocalContext: (session, credential) async =>
          sessionJustCreated || await _hasLocalContext(session, credential),
    );
    if (resolved is! CashierModeState) cashierName = null;
    return resolved;
  }

  /// Offline continuation needs the cached shop, active cashier, this exact
  /// registered device and at least one product.
  Future<bool> _hasLocalContext(
    CashierSession session,
    DeviceCredential credential,
  ) async {
    final stableIdentifier = await AppDeviceIdProvider(
      PreferencesDeviceIdStore(),
      const UuidV7Generator(),
    ).getOrCreate();
    if (stableIdentifier != credential.deviceIdentifier) return false;
    final db = await AppDatabase.open();
    try {
      final shop = await (db.select(
        db.shops,
      )..where((row) => row.id.equals(session.shopId))).getSingleOrNull();
      final cashier =
          await (db.select(db.cashiers)..where(
                (row) =>
                    row.id.equals(session.cashierId) &
                    row.shopId.equals(session.shopId) &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      final device =
          await (db.select(db.devices)..where(
                (row) =>
                    row.id.equals(session.deviceId) &
                    row.shopId.equals(session.shopId) &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      final productCount =
          await (db.selectOnly(db.shopProducts)
                ..addColumns([db.shopProducts.id.count()])
                ..where(
                  db.shopProducts.shopId.equals(session.shopId) &
                      db.shopProducts.isActive.equals(true),
                ))
              .map((row) => row.read(db.shopProducts.id.count()) ?? 0)
              .getSingle();
      if (shop == null ||
          cashier == null ||
          device == null ||
          device.deviceIdentifier != stableIdentifier ||
          productCount == 0) {
        return false;
      }
      cashierName = cashier.displayName;
      return true;
    } finally {
      await db.close();
    }
  }

  SupabaseClient _clientFor(DeviceCredential credential) {
    final current = _deviceClient;
    if (current != null &&
        _deviceClientCredential?.headerValue == credential.headerValue) {
      return current;
    }
    current?.dispose();
    _deviceClientCredential = credential;
    return _deviceClient = deviceSupabaseClient(
      url: AppEnvironment.supabaseUrl,
      anonKey: AppEnvironment.supabaseAnonKey,
      credential: credential,
    );
  }

  Future<void> _exitCashier(SupabaseClient deviceClient) async {
    try {
      await CashierSessionManager(
        SupabaseCashierAuthGateway(deviceClient),
        SecureCashierSessionStore(),
      ).logout();
    } catch (_) {
      // logout() clears local credentials in finally. A failed remote revoke is
      // not shown as a successful server revoke, but must not trap the UI.
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => DeviceModeScope(
    startCashierMode: _startCashier,
    reload: _reload,
    child: FutureBuilder<DeviceModeState>(
      future: state,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final resolved = snapshot.data;
        if (snapshot.hasError || resolved == null) {
          return _Problem(
            message: 'This device could not be opened. Try again.',
            onRetry: _reload,
          );
        }
        return switch (resolved) {
          OwnerModeState() => widget.child,
          OwnerSignInRequiredState(:final warning) => _withWarning(
            widget.child,
            warning,
          ),
          OwnerRemovalFailedState() => _Problem(
            message:
                'Owner mode could not be closed safely on this device, so cashier mode was not opened. Restart the app and try again.',
            onRetry: _reload,
          ),
          DeviceLobbyState(:final credential, :final warning) =>
            ownerSignInRequested
                ? _OwnerSignIn(
                    client: widget.client,
                    onBack: _reload,
                    child: widget.child,
                  )
                : _withWarning(
                    _DeviceLobby(
                      credential: credential,
                      client: _clientFor(credential),
                      onAuthenticated: (_, name) => _startCashier(name),
                      onOwnerSignIn: () =>
                          setState(() => ownerSignInRequested = true),
                    ),
                    warning,
                  ),
          CashierModeState(:final credential, :final session) => () {
            final deviceClient = _clientFor(credential);
            return PosRuntime(
              client: deviceClient,
              shopId: session.shopId,
              shopName: credential.shopName,
              cashierId: session.cashierId,
              cashierName: cashierName ?? 'Cashier',
              deviceId: session.deviceId,
              onExit: () => _exitCashier(deviceClient),
            );
          }(),
        };
      },
    ),
  );

  Widget _withWarning(Widget child, String? warning) {
    if (warning == null) return child;
    return Stack(
      children: [
        child,
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(warning),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Provisioned device without a cashier session: cashier login with the
/// device credential (no cashier setup), or the owner's sign-in.
class _DeviceLobby extends StatelessWidget {
  const _DeviceLobby({
    required this.credential,
    required this.client,
    required this.onAuthenticated,
    required this.onOwnerSignIn,
  });
  final DeviceCredential credential;
  final SupabaseClient client;
  final void Function(CashierSession session, String cashierName)
  onAuthenticated;
  final VoidCallback onOwnerSignIn;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(credential.shopName)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            CashierLoginPanel(
              client: client,
              shopId: credential.shopId,
              shopName: credential.shopName,
              deviceIdentifier: credential.deviceIdentifier,
              directory: DeviceCashierDirectory(client),
              onAuthenticated: onAuthenticated,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const ValueKey('lobby-owner-sign-in'),
              onPressed: onOwnerSignIn,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Owner sign in'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The owner sign-in form, with a way back to the cashier lobby until the
/// owner has actually signed in.
class _OwnerSignIn extends StatelessWidget {
  const _OwnerSignIn({
    required this.client,
    required this.onBack,
    required this.child,
  });
  final SupabaseClient client;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: client.auth.onAuthStateChange,
    builder: (context, _) => Stack(
      children: [
        child,
        if (client.auth.currentSession == null)
          Positioned(
            left: 16,
            bottom: 16,
            child: SafeArea(
              child: OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to cashier login'),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    ),
  );
}
