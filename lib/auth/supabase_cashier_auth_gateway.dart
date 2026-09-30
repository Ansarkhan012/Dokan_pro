import 'package:supabase_flutter/supabase_flutter.dart';
import 'cashier_auth_gateway.dart';
import 'cashier_session.dart';

final class SupabaseCashierAuthGateway implements CashierAuthGateway {
  SupabaseCashierAuthGateway(this.client);
  final SupabaseClient client;
  @override
  Future<CashierSession> authenticate({
    required String shopId,
    required String deviceIdentifier,
    required String cashierId,
    required String pin,
  }) async {
    final result = await client.rpc(
      'authenticate_cashier',
      params: {
        'p_shop_id': shopId,
        'p_device_identifier': deviceIdentifier,
        'p_cashier_id': cashierId,
        'p_pin': pin,
      },
    );
    final row = (result as List<dynamic>).single as Map<String, dynamic>;
    return CashierSession(
      token: row['session_token']! as String,
      shopId: row['shop_id']! as String,
      cashierId: row['cashier_id']! as String,
      deviceId: row['device_id']! as String,
      expiresAt: DateTime.parse(row['expires_at']! as String),
    );
  }

  @override
  Future<bool> validate(CashierSession session) async {
    final result = await client.rpc(
      'validate_cashier_session',
      params: {
        'p_session_token': session.token,
        'p_shop_id': session.shopId,
        'p_device_id': session.deviceId,
      },
    );
    return result != null;
  }

  @override
  Future<void> revoke(CashierSession session) async {
    await client.rpc(
      'revoke_cashier_session',
      params: {'p_session_token': session.token},
    );
  }
}
