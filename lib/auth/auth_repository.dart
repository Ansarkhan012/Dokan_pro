import 'domain/auth_state.dart';

abstract interface class AuthRepository {
  AppAuthState get current;
  Stream<AppAuthState> get changes;
  Future<void> signIn({required String email, required String password});

  /// Shops and owner accounts are created by Dokan Pro Support; there is no
  /// self-registration. An owner who forgot their password gets a reset link.
  Future<void> sendPasswordReset({required String email});
  Future<void> signOut();
}
