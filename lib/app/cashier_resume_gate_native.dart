import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/cashier_session.dart';
import '../auth/cashier_session_manager.dart';
import '../auth/cashier_session_store.dart';
import '../auth/supabase_cashier_auth_gateway.dart';
import '../database/app_database.dart';
import '../features/pos/pos_runtime.dart';
import '../core/device/app_device_id.dart';
import '../core/device/preferences_device_id_store.dart';
import '../core/ids/id_generator.dart';

class CashierResumeGate extends StatefulWidget {
  const CashierResumeGate({
    super.key,
    required this.client,
    required this.child,
  });

  final SupabaseClient client;
  final Widget child;

  @override
  State<CashierResumeGate> createState() => _CashierResumeGateState();
}

class _CashierResumeGateState extends State<CashierResumeGate> {
  late Future<_ResumeState?> resume = _load();
  String? resumeWarning;

  Future<_ResumeState?> _load() async {
    final store = SecureCashierSessionStore();
    final session = await store.read();
    // An authenticated owner must resolve their own shop before any cashier
    // context is shown. This prevents owner A from entering a cached Shop B
    // cashier session through the startup shortcut.
    if (widget.client.auth.currentUser != null) return null;
    if (session == null || !session.isLocallyValidAt(DateTime.now().toUtc())) {
      if (session != null) {
        await store.clear();
        resumeWarning =
            'The offline cashier session expired. Connect to the internet and sign in again.';
      }
      return null;
    }
    final stableIdentifier = await AppDeviceIdProvider(
      PreferencesDeviceIdStore(),
      const UuidV7Generator(),
    ).getOrCreate();
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
        await store.clear();
        resumeWarning =
            'Offline cashier access is unavailable because this shop or device no longer matches. Connect to the internet and sign in again.';
        return null;
      }
      return _ResumeState(
        session: session,
        shopName: shop.name,
        cashierName: cashier.displayName,
      );
    } finally {
      await db.close();
    }
  }

  Future<void> _exitCashier() async {
    try {
      await CashierSessionManager(
        SupabaseCashierAuthGateway(widget.client),
        SecureCashierSessionStore(),
      ).logout();
    } catch (_) {
      // logout() clears local credentials in finally. A failed remote revoke is
      // not shown as a successful server revoke, but must not trap the UI.
    }
    if (mounted) setState(() => resume = Future.value(null));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ResumeState?>(
    future: resume,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final cached = snapshot.data;
      if (cached == null) {
        final warning = resumeWarning;
        if (warning == null) return widget.child;
        return Stack(
          children: [
            widget.child,
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
      return PosRuntime(
        client: widget.client,
        shopId: cached.session.shopId,
        shopName: cached.shopName,
        cashierId: cached.session.cashierId,
        cashierName: cached.cashierName,
        deviceId: cached.session.deviceId,
        onExit: _exitCashier,
      );
    },
  );
}

final class _ResumeState {
  const _ResumeState({
    required this.session,
    required this.shopName,
    required this.cashierName,
  });

  final CashierSession session;
  final String shopName;
  final String cashierName;
}
