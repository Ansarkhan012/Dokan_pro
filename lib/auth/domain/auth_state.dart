enum AppAuthStatus { signedOut, authenticated }

final class AppAuthState {
  const AppAuthState._(this.status, this.userId, this.email);
  const AppAuthState.signedOut() : this._(AppAuthStatus.signedOut, null, null);
  const AppAuthState.authenticated({required String userId, String? email})
    : this._(AppAuthStatus.authenticated, userId, email);
  final AppAuthStatus status;
  final String? userId;
  final String? email;
}

AppAuthState mapAuthIdentity({String? userId, String? email}) => userId == null
    ? const AppAuthState.signedOut()
    : AppAuthState.authenticated(userId: userId, email: email);
