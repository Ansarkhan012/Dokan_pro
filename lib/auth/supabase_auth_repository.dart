import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_repository.dart';
import 'domain/auth_state.dart';

final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client);
  final SupabaseClient client;

  AppAuthState _map(User? user) =>
      mapAuthIdentity(userId: user?.id, email: user?.email);

  @override
  AppAuthState get current => _map(client.auth.currentUser);
  @override
  Stream<AppAuthState> get changes =>
      client.auth.onAuthStateChange.map((event) => _map(event.session?.user));
  @override
  Future<void> signIn({required String email, required String password}) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}
