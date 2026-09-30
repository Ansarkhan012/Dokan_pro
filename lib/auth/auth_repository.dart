import 'domain/auth_state.dart';

abstract interface class AuthRepository {
  AppAuthState get current;
  Stream<AppAuthState> get changes;
  Future<void> signIn({required String email, required String password});
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  });
  Future<void> signOut();
}
