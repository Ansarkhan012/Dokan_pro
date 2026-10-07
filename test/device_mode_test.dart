import 'package:dukaan_pro/auth/cashier_session.dart';
import 'package:dukaan_pro/auth/cashier_session_store.dart';
import 'package:dukaan_pro/auth/device_credential.dart';
import 'package:dukaan_pro/auth/device_mode.dart';
import 'package:dukaan_pro/auth/owner_mode_lock.dart';
import 'package:flutter_test/flutter_test.dart';

const _shop = 'shop-a';
const _device = 'device-a';
final _now = DateTime.utc(2026, 10, 7, 10);

DeviceCredential _credential({String shop = _shop, String device = _device}) =>
    DeviceCredential(
      shopId: shop,
      shopName: 'Shop A',
      deviceId: device,
      deviceIdentifier: 'identifier-a',
      secret: 'a' * 64,
    );

CashierSession _session({String device = _device, DateTime? expiresAt}) =>
    CashierSession(
      token: 'cashier-token',
      shopId: _shop,
      cashierId: 'cashier-1',
      deviceId: device,
      expiresAt: expiresAt ?? _now.add(const Duration(hours: 6)),
    );

void main() {
  late _FakeOwner owner;
  late _MemoryCredentials credentials;
  late _MemorySessions sessions;
  late _MemoryLock lock;
  late DeviceModeService service;

  setUp(() {
    owner = _FakeOwner();
    credentials = _MemoryCredentials();
    sessions = _MemorySessions();
    lock = _MemoryLock();
    service = DeviceModeService(
      owner: owner,
      credentials: credentials,
      cashierSessions: sessions,
      lockStore: lock,
      clock: () => _now,
    );
  });

  Future<DeviceModeState> resolve({bool localContext = true}) =>
      service.resolve(hasLocalContext: (_, _) async => localContext);

  group('entering cashier mode', () {
    test('removes the owner session and opens the cashier session', () async {
      owner.signedIn = true;
      lock.locked = true; // engaged by enterCashierMode
      credentials.value = _credential();
      sessions.value = _session();

      final state = await resolve();

      expect(state, isA<CashierModeState>());
      expect(owner.removals, 1);
      expect(owner.signedIn, isFalse);
      expect(owner.persistedToken, isFalse, reason: 'no refresh token left');
    });

    test('does not open cashier mode when the owner session survives', () async {
      owner
        ..signedIn = true
        ..removalWorks = false;
      lock.locked = true;
      credentials.value = _credential();
      sessions.value = _session();

      expect(await resolve(), isA<OwnerRemovalFailedState>());
      expect(sessions.value, isNotNull, reason: 'nothing opened or discarded');
    });

    test('an unreadable lock with an owner session fails closed', () async {
      owner.signedIn = true;
      lock.failRead = true;
      credentials.value = _credential();

      expect(await resolve(), isA<DeviceLobbyState>());
      expect(owner.signedIn, isFalse);
    });
  });

  group('owner mode', () {
    test('an unlocked owner session stays in owner mode untouched', () async {
      owner.signedIn = true;
      credentials.value = _credential();
      sessions.value = _session();

      expect(await resolve(), isA<OwnerModeState>());
      expect(owner.removals, 0);
    });

    test('after leaving cashier mode only an owner sign-in restores owner mode', () async {
      credentials.value = _credential();
      lock.locked = true;
      expect(await resolve(), isA<DeviceLobbyState>(), reason: 'lobby, not owner');

      owner.signedIn = true; // a real sign-in releases the lock (AuthForm)
      lock.locked = false;
      expect(await resolve(), isA<OwnerModeState>());
    });
  });

  group('offline restart', () {
    test('resumes cashier mode with no owner session and no network', () async {
      lock.locked = true;
      credentials.value = _credential();
      sessions.value = _session();

      final state = await resolve();

      expect(state, isA<CashierModeState>());
      expect((state as CashierModeState).credential.deviceId, _device);
      expect(owner.removals, 0);
    });

    test('an expired cashier session returns to the lobby', () async {
      credentials.value = _credential();
      sessions.value = _session(expiresAt: _now.subtract(const Duration(minutes: 1)));

      final state = await resolve();

      expect(state, isA<DeviceLobbyState>());
      expect((state as DeviceLobbyState).warning, contains('expired'));
      expect(sessions.value, isNull);
    });

    test('a session of another device or missing local data is not resumed', () async {
      credentials.value = _credential();
      sessions.value = _session(device: 'device-b');
      expect(await resolve(), isA<DeviceLobbyState>());
      expect(sessions.value, isNull);

      sessions.value = _session();
      expect(await resolve(localContext: false), isA<DeviceLobbyState>());
      expect(sessions.value, isNull);
    });
  });

  group('upgrade and provisioning', () {
    test('an upgraded tablet without a credential fails closed to owner sign-in', () async {
      // Left by the previous app version: owner session under a locked owner
      // mode and a cached cashier session, but no device credential.
      owner.signedIn = true;
      lock.locked = true;
      sessions.value = _session();

      final state = await resolve();

      expect(state, isA<OwnerSignInRequiredState>());
      expect((state as OwnerSignInRequiredState).warning, isNotNull);
      expect(owner.signedIn, isFalse, reason: 'never kept under cashier mode');
      expect(sessions.value, isNull);
    });

    test('provisioning needs a verified owner', () async {
      final issuer = _FakeIssuer();
      await expectLater(
        service.ensureCredential(
          shopId: _shop,
          shopName: 'Shop A',
          deviceId: _device,
          deviceIdentifier: 'identifier-a',
          ownerVerified: false,
          issuer: issuer,
        ),
        throwsA(isA<DeviceNotProvisioned>()),
      );
      expect(issuer.calls, 0);
      expect(credentials.value, isNull);

      final credential = await service.ensureCredential(
        shopId: _shop,
        shopName: 'Shop A',
        deviceId: _device,
        deviceIdentifier: 'identifier-a',
        ownerVerified: true,
        issuer: issuer,
      );
      expect(issuer.calls, 1);
      expect(credential.secret, 'f' * 64);
      expect(credentials.value?.headerValue, '$_device.${'f' * 64}');
    });

    test('an existing credential is reused; another device\'s is replaced', () async {
      final issuer = _FakeIssuer();
      credentials.value = _credential();
      await service.ensureCredential(
        shopId: _shop,
        shopName: 'Shop A',
        deviceId: _device,
        deviceIdentifier: 'identifier-a',
        ownerVerified: false,
        issuer: issuer,
      );
      expect(issuer.calls, 0);

      credentials.value = _credential(device: 'device-old');
      await expectLater(
        service.ensureCredential(
          shopId: _shop,
          shopName: 'Shop A',
          deviceId: _device,
          deviceIdentifier: 'identifier-a',
          ownerVerified: false,
          issuer: issuer,
        ),
        throwsA(isA<DeviceNotProvisioned>()),
      );
      await service.ensureCredential(
        shopId: _shop,
        shopName: 'Shop A',
        deviceId: _device,
        deviceIdentifier: 'identifier-a',
        ownerVerified: true,
        issuer: issuer,
      );
      expect(credentials.value?.deviceId, _device);
    });

    test('a failed provisioning stores nothing', () async {
      await expectLater(
        service.ensureCredential(
          shopId: _shop,
          shopName: 'Shop A',
          deviceId: _device,
          deviceIdentifier: 'identifier-a',
          ownerVerified: true,
          issuer: _FakeIssuer(fail: true),
        ),
        throwsA(isA<StateError>()),
      );
      expect(credentials.value, isNull);
    });

    test('the credential never appears in its string form', () {
      expect(_credential().toString(), isNot(contains('a' * 64)));
    });
  });
}

final class _FakeOwner implements OwnerAuthority {
  bool signedIn = false;
  bool persistedToken = false;
  bool removalWorks = true;
  int removals = 0;

  @override
  bool get isSignedIn => signedIn;

  @override
  Future<void> removeLocalSession() async {
    removals++;
    if (removalWorks) {
      signedIn = false;
      persistedToken = false;
    }
  }

  @override
  Future<bool> isGone() async => !signedIn && !persistedToken;
}

final class _MemoryCredentials implements DeviceCredentialStore {
  DeviceCredential? value;
  @override
  Future<DeviceCredential?> read() async => value;
  @override
  Future<void> write(DeviceCredential credential) async => value = credential;
  @override
  Future<void> clear() async => value = null;
}

final class _MemorySessions implements CashierSessionStore {
  CashierSession? value;
  @override
  Future<CashierSession?> read() async => value;
  @override
  Future<void> write(CashierSession session) async => value = session;
  @override
  Future<void> clear() async => value = null;
}

final class _MemoryLock implements OwnerModeLockStore {
  bool locked = false;
  bool failRead = false;
  @override
  Future<bool> read() async {
    if (failRead) throw StateError('unreadable');
    return locked;
  }

  @override
  Future<void> write(bool value) async => locked = value;
}

final class _FakeIssuer implements DeviceCredentialIssuer {
  _FakeIssuer({this.fail = false});
  final bool fail;
  int calls = 0;
  @override
  Future<String> issue({required String shopId, required String deviceId}) async {
    calls++;
    if (fail) throw StateError('offline');
    return 'f' * 64;
  }
}
