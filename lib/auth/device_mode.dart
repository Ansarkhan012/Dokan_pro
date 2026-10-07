import 'package:supabase_flutter/supabase_flutter.dart';
import 'cashier_session.dart';
import 'cashier_session_store.dart';
import 'device_credential.dart';
import 'owner_mode_lock.dart';

/// The owner's Supabase session on this device, as cashier mode sees it.
abstract interface class OwnerAuthority {
  bool get isSignedIn;

  /// Removes the local owner session (memory and persisted storage). Never
  /// throws for a server-side revocation that cannot be reached.
  Future<void> removeLocalSession();

  /// True when no owner access or refresh token remains on this device.
  Future<bool> isGone();
}

final class SupabaseOwnerAuthority implements OwnerAuthority {
  SupabaseOwnerAuthority(this.client, this.storage);
  final SupabaseClient client;

  /// The storage the owner session is persisted in (see main.dart).
  final LocalStorage storage;

  @override
  bool get isSignedIn => client.auth.currentSession != null;

  @override
  Future<void> removeLocalSession() async {
    try {
      // Local scope removes the in-memory session first, then asks the server
      // to revoke this refresh token; offline, only the server call fails.
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The local copy is removed below regardless.
    }
    // supabase_flutter deletes the persisted copy in a listener it does not
    // await; delete it here so the result can be verified.
    await storage.removePersistedSession();
  }

  @override
  Future<bool> isGone() async =>
      client.auth.currentSession == null && !await storage.hasAccessToken();
}

/// A device without a credential cannot enter cashier mode until the owner
/// proves identity on it (a real sign-in or the owner password).
final class DeviceNotProvisioned implements Exception {
  const DeviceNotProvisioned();
}

/// The owner session could not be verifiably removed; cashier mode must not
/// start on top of it.
final class OwnerAuthorityRetained implements Exception {
  const OwnerAuthorityRetained();
}

sealed class DeviceModeState {
  const DeviceModeState();
}

/// The owner is signed in and owner mode is unlocked: the owner hub.
final class OwnerModeState extends DeviceModeState {
  const OwnerModeState();
}

/// No usable credential: the owner must sign in (online) to provision.
final class OwnerSignInRequiredState extends DeviceModeState {
  const OwnerSignInRequiredState({this.warning});
  final String? warning;
}

/// Provisioned device, no cashier session: cashier login or owner sign-in.
final class DeviceLobbyState extends DeviceModeState {
  const DeviceLobbyState(this.credential, {this.warning});
  final DeviceCredential credential;
  final String? warning;
}

/// A cashier session that may continue on this device, online or offline.
final class CashierModeState extends DeviceModeState {
  const CashierModeState(this.credential, this.session);
  final DeviceCredential credential;
  final CashierSession session;
}

/// The owner session could not be removed; nothing cashier-facing is shown.
final class OwnerRemovalFailedState extends DeviceModeState {
  const OwnerRemovalFailedState();
}

/// Decides which side of the owner/cashier boundary the device is on, and
/// moves it across safely. Cashier mode never runs with an owner session on
/// the device: a locked owner session (cashier mode was entered, interrupted
/// or left behind by an older app version) is removed before anything else.
final class DeviceModeService {
  DeviceModeService({
    required this.owner,
    required this.credentials,
    required this.cashierSessions,
    required this.lockStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OwnerAuthority owner;
  final DeviceCredentialStore credentials;
  final CashierSessionStore cashierSessions;
  final OwnerModeLockStore lockStore;
  final DateTime Function() _clock;

  /// Removes the owner session and verifies that no token remains.
  Future<void> removeOwnerAuthority() async {
    await owner.removeLocalSession();
    if (!await owner.isGone()) throw const OwnerAuthorityRetained();
  }

  /// The device credential for this shop and device. Provisions (or replaces
  /// a credential of another shop/device) only when [ownerVerified]: the
  /// owner proved identity on this device since cashier mode last ran.
  Future<DeviceCredential> ensureCredential({
    required String shopId,
    required String shopName,
    required String deviceId,
    required String deviceIdentifier,
    required bool ownerVerified,
    required DeviceCredentialIssuer issuer,
  }) async {
    final stored = await credentials.read();
    if (stored != null && stored.belongsTo(shopId: shopId, deviceId: deviceId)) {
      return stored;
    }
    if (!ownerVerified) throw const DeviceNotProvisioned();
    final credential = DeviceCredential(
      shopId: shopId,
      shopName: shopName,
      deviceId: deviceId,
      deviceIdentifier: deviceIdentifier,
      secret: await issuer.issue(shopId: shopId, deviceId: deviceId),
    );
    await credentials.write(credential);
    return credential;
  }

  /// Startup and every return from a mode change. [hasLocalContext] checks the
  /// cached shop, cashier, device and products for offline continuation.
  Future<DeviceModeState> resolve({
    required Future<bool> Function(CashierSession session, DeviceCredential credential)
    hasLocalContext,
  }) async {
    bool locked;
    try {
      locked = await lockStore.read();
    } catch (_) {
      locked = true; // An unreadable lock fails closed.
    }
    if (owner.isSignedIn) {
      if (!locked) return const OwnerModeState();
      try {
        await removeOwnerAuthority();
      } on OwnerAuthorityRetained {
        return const OwnerRemovalFailedState();
      }
    }
    final credential = await credentials.read();
    final session = await cashierSessions.read();
    if (credential == null) {
      if (session == null) return const OwnerSignInRequiredState();
      await cashierSessions.clear();
      return const OwnerSignInRequiredState(
        warning:
            'This device must be set up for cashier mode once. Ask the owner to sign in.',
      );
    }
    if (session == null) return DeviceLobbyState(credential);
    if (!session.isLocallyValidAt(_clock().toUtc())) {
      await cashierSessions.clear();
      return DeviceLobbyState(
        credential,
        warning:
            'The offline cashier session expired. Connect to the internet and sign in again.',
      );
    }
    if (!session.belongsToDevice(credential) ||
        !await hasLocalContext(session, credential)) {
      await cashierSessions.clear();
      return DeviceLobbyState(
        credential,
        warning:
            'Offline cashier access is unavailable because this shop or device no longer matches. Connect to the internet and sign in again.',
      );
    }
    return CashierModeState(credential, session);
  }
}

extension on CashierSession {
  bool belongsToDevice(DeviceCredential credential) =>
      credential.belongsTo(shopId: shopId, deviceId: deviceId);
}
