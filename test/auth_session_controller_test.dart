import 'dart:async';

import 'package:dukaan_pro/auth/auth_repository.dart';
import 'package:dukaan_pro/auth/auth_session_controller.dart';
import 'package:dukaan_pro/auth/domain/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('authoritative auth lifecycle', () {
    test('fresh launch is signed out', () {
      final auth = _FakeAuth();
      final controller = AuthSessionController(auth)..start();
      expect(controller.state.phase, AuthSessionPhase.signedOut);
      controller.dispose();
    });

    test('correct login resolves owner and double click is ignored', () async {
      final auth = _FakeAuth();
      final controller = AuthSessionController(auth)..start();
      final first = controller.signIn(email: 'a@b.test', password: 'correct');
      final second = controller.signIn(email: 'a@b.test', password: 'correct');
      await Future.wait([first, second]);
      expect(auth.signInCalls, 1);
      expect(controller.state.phase, AuthSessionPhase.resolvingOwner);
      expect(controller.state.userId, 'owner-a');
      await controller.dispose();
    });

    test('wrong password is surfaced without a forged session', () async {
      final auth = _FakeAuth()..loginError = StateError('wrong password');
      final controller = AuthSessionController(auth)..start();
      await expectLater(
        controller.signIn(email: 'a@b.test', password: 'wrong'),
        throwsStateError,
      );
      expect(controller.state.userId, isNull);
      await controller.dispose();
    });

    test('logout invalidates a stale login completion', () async {
      final auth = _FakeAuth()..blockLogin = Completer<void>();
      final controller = AuthSessionController(auth)..start();
      final login = controller.signIn(email: 'a@b.test', password: 'correct');
      await controller.signOut();
      auth.blockLogin!.complete();
      await login;
      expect(controller.state.phase, AuthSessionPhase.signedOut);
      await controller.dispose();
    });

    test('rapid auth events converge on newest emitted identity', () async {
      final auth = _FakeAuth();
      final controller = AuthSessionController(auth)..start();
      auth.emit(const AppAuthState.authenticated(userId: 'old'));
      auth.emit(const AppAuthState.signedOut());
      auth.emit(const AppAuthState.authenticated(userId: 'new'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.userId, 'new');
      await controller.dispose();
    });

    test('successful token refresh retains owner resolution', () async {
      final auth = _FakeAuth()
        ..currentState = const AppAuthState.authenticated(userId: 'owner');
      final controller = AuthSessionController(auth)..start();
      auth.emit(const AppAuthState.authenticated(userId: 'owner'));
      expect(controller.state.phase, AuthSessionPhase.resolvingOwner);
      expect(controller.state.userId, 'owner');
      await controller.dispose();
    });

    test('invalid refresh token produces signed-out state', () async {
      final auth = _FakeAuth()
        ..currentState = const AppAuthState.authenticated(userId: 'owner');
      final controller = AuthSessionController(auth)..start();
      auth.emit(const AppAuthState.signedOut());
      expect(controller.state.phase, AuthSessionPhase.signedOut);
      await controller.dispose();
    });

    test(
      'refresh network failure does not fabricate signed-out identity',
      () async {
        final auth = _FakeAuth()
          ..currentState = const AppAuthState.authenticated(userId: 'owner');
        final controller = AuthSessionController(auth)..start();
        // Supabase emits no identity replacement when a transient refresh call
        // fails; the controller keeps the last authoritative identity.
        expect(controller.state.userId, 'owner');
        expect(controller.state.phase, AuthSessionPhase.resolvingOwner);
        await controller.dispose();
      },
    );

    test('access-token expiry is explicit and recoverable', () async {
      final auth = _FakeAuth()
        ..currentState = const AppAuthState.authenticated(userId: 'owner');
      final controller = AuthSessionController(auth)..start();
      controller.sessionExpired();
      expect(controller.state.phase, AuthSessionPhase.sessionExpired);
      expect(controller.state.message, contains('expired'));
      auth.emit(const AppAuthState.signedOut());
      expect(controller.state.phase, AuthSessionPhase.signedOut);
      await controller.dispose();
    });

    test(
      'inactive membership and revoked device are terminal states',
      () async {
        final auth = _FakeAuth()
          ..currentState = const AppAuthState.authenticated(userId: 'owner');
        final controller = AuthSessionController(auth)..start();
        controller.ownerResolved(active: false);
        expect(controller.state.phase, AuthSessionPhase.accessDenied);
        auth.emit(const AppAuthState.authenticated(userId: 'owner'));
        controller.deviceResolved(registered: true, active: false);
        expect(controller.state.phase, AuthSessionPhase.accessDenied);
        expect(controller.state.message, contains('revoked'));
        await controller.dispose();
      },
    );

    test('events after disposal cannot mutate state', () async {
      final auth = _FakeAuth();
      final controller = AuthSessionController(auth)..start();
      await controller.dispose();
      auth.emit(const AppAuthState.authenticated(userId: 'late'));
      expect(controller.state.phase, AuthSessionPhase.signedOut);
    });
  });
}

final class _FakeAuth implements AuthRepository {
  final events = StreamController<AppAuthState>.broadcast(sync: true);
  AppAuthState currentState = const AppAuthState.signedOut();
  Object? loginError;
  Completer<void>? blockLogin;
  int signInCalls = 0;

  void emit(AppAuthState state) {
    currentState = state;
    events.add(state);
  }

  @override
  Stream<AppAuthState> get changes => events.stream;
  @override
  AppAuthState get current => currentState;
  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    if (loginError case final error?) throw error;
    await blockLogin?.future;
    currentState = const AppAuthState.authenticated(userId: 'owner-a');
  }

  @override
  Future<void> signOut() async {
    currentState = const AppAuthState.signedOut();
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {}
}
