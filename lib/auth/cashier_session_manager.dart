import 'cashier_auth_gateway.dart';
import 'cashier_session.dart';
import 'cashier_session_store.dart';

final class CashierSessionManager {
  CashierSessionManager(this.gateway, this.store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final CashierAuthGateway gateway;
  final CashierSessionStore store;
  final DateTime Function() _clock;
  Future<CashierSession> login({
    required String shopId,
    required String deviceIdentifier,
    required String cashierId,
    required String pin,
  }) async {
    final session = await gateway.authenticate(
      shopId: shopId,
      deviceIdentifier: deviceIdentifier,
      cashierId: cashierId,
      pin: pin,
    );
    await store.write(session);
    return session;
  }

  Future<bool> canContinueOffline() async =>
      (await store.read())?.isLocallyValidAt(_clock().toUtc()) ?? false;

  /// Offline continuation is allowed only for the already-provisioned shop and
  /// registered device, with the minimum local reference data available.
  Future<CashierSession?> restoreForContext({
    required String shopId,
    required String deviceId,
    required bool hasRequiredLocalData,
  }) async {
    final session = await store.read();
    final valid =
        session != null &&
        session.isLocallyValidAt(_clock().toUtc()) &&
        session.shopId == shopId &&
        session.deviceId == deviceId &&
        hasRequiredLocalData;
    if (!valid) {
      await store.clear();
      return null;
    }
    return session;
  }

  Future<bool> validateOnline() async {
    final session = await store.read();
    if (session == null || !session.isLocallyValidAt(_clock())) {
      await store.clear();
      return false;
    }
    final valid = await gateway.validate(session);
    if (!valid) await store.clear();
    return valid;
  }

  Future<void> logout({bool notifyServer = true}) async {
    final session = await store.read();
    try {
      if (notifyServer && session != null) await gateway.revoke(session);
    } finally {
      // A backend outage must never leave a reusable local cashier credential
      // behind after the cashier explicitly logs out.
      await store.clear();
    }
  }
}
