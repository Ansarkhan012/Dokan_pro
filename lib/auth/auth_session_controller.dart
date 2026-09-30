import 'dart:async';

import 'auth_repository.dart';
import 'domain/auth_state.dart';

enum AuthSessionPhase {
  initializing,
  signedOut,
  authenticating,
  resolvingOwner,
  ownerReady,
  deviceRegistrationRequired,
  cashierSelectionRequired,
  cashierAuthenticating,
  cashierReady,
  offlineCashierReady,
  sessionExpired,
  accessDenied,
  error,
}

final class AuthSessionState {
  const AuthSessionState(this.phase, {this.userId, this.message});
  final AuthSessionPhase phase;
  final String? userId;
  final String? message;
}

/// Serializes owner-auth transitions. Every asynchronous request captures a
/// generation; a logout, newer auth event, or disposal invalidates old work.
final class AuthSessionController {
  AuthSessionController(this._auth);

  final AuthRepository _auth;
  final _states = StreamController<AuthSessionState>.broadcast();
  StreamSubscription<AppAuthState>? _subscription;
  var _generation = 0;
  var _disposed = false;
  var _signingIn = false;
  AuthSessionState _state = const AuthSessionState(
    AuthSessionPhase.initializing,
  );

  AuthSessionState get state => _state;
  Stream<AuthSessionState> get states => _states.stream;
  bool get signingIn => _signingIn;

  void start() {
    if (_disposed || _subscription != null) return;
    _subscription = _auth.changes.listen(_acceptIdentity);
    _acceptIdentity(_auth.current);
  }

  Future<void> signIn({required String email, required String password}) async {
    if (_disposed || _signingIn) return;
    _signingIn = true;
    final request = ++_generation;
    _emit(const AuthSessionState(AuthSessionPhase.authenticating));
    try {
      await _auth.signIn(email: email, password: password);
      if (!_isCurrent(request)) return;
      final current = _auth.current;
      if (current.userId == null) {
        _emit(
          const AuthSessionState(
            AuthSessionPhase.error,
            message: 'Sign in did not create a valid session.',
          ),
        );
      } else {
        _emit(
          AuthSessionState(
            AuthSessionPhase.resolvingOwner,
            userId: current.userId,
          ),
        );
      }
    } catch (_) {
      if (_isCurrent(request)) rethrow;
    } finally {
      if (_isCurrent(request)) _signingIn = false;
    }
  }

  Future<void> signOut() async {
    if (_disposed) return;
    ++_generation;
    _signingIn = false;
    try {
      await _auth.signOut();
    } finally {
      if (!_disposed) {
        _emit(const AuthSessionState(AuthSessionPhase.signedOut));
      }
    }
  }

  void ownerResolved({required bool active}) {
    if (_state.userId == null) return;
    _emit(
      AuthSessionState(
        active ? AuthSessionPhase.ownerReady : AuthSessionPhase.accessDenied,
        userId: _state.userId,
        message: active ? null : 'Your shop membership is inactive.',
      ),
    );
  }

  void deviceResolved({required bool registered, required bool active}) {
    if (!registered) {
      _emit(
        AuthSessionState(
          AuthSessionPhase.deviceRegistrationRequired,
          userId: _state.userId,
        ),
      );
    } else if (!active) {
      _emit(
        AuthSessionState(
          AuthSessionPhase.accessDenied,
          userId: _state.userId,
          message: 'This device has been revoked.',
        ),
      );
    } else {
      _emit(
        AuthSessionState(
          AuthSessionPhase.cashierSelectionRequired,
          userId: _state.userId,
        ),
      );
    }
  }

  void cashierAuthenticationStarted() => _emit(
    AuthSessionState(
      AuthSessionPhase.cashierAuthenticating,
      userId: _state.userId,
    ),
  );

  void cashierResolved({required bool offline}) => _emit(
    AuthSessionState(
      offline
          ? AuthSessionPhase.offlineCashierReady
          : AuthSessionPhase.cashierReady,
      userId: _state.userId,
    ),
  );

  void sessionExpired() => _emit(
    AuthSessionState(
      AuthSessionPhase.sessionExpired,
      userId: _state.userId,
      message: 'Your session expired. Please sign in again.',
    ),
  );

  void _acceptIdentity(AppAuthState identity) {
    if (_disposed) return;
    ++_generation;
    _signingIn = false;
    _emit(
      identity.userId == null
          ? const AuthSessionState(AuthSessionPhase.signedOut)
          : AuthSessionState(
              AuthSessionPhase.resolvingOwner,
              userId: identity.userId,
            ),
    );
  }

  bool _isCurrent(int request) => !_disposed && request == _generation;

  void _emit(AuthSessionState next) {
    if (_disposed) return;
    _state = next;
    _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    await _subscription?.cancel();
    await _states.close();
  }
}
