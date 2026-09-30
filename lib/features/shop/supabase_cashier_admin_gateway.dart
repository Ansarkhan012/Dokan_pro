import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/ids/id_generator.dart';
import 'cashier_admin_gateway.dart';

final class SupabaseCashierAdminGateway implements CashierAdminGateway {
  SupabaseCashierAdminGateway(this.client);
  final SupabaseClient client;

  @override
  Future<List<CashierMetadata>> cashiers({required String shopId}) async {
    final rows = await client
        .from('cashiers')
        .select('id,display_name,is_active')
        .eq('shop_id', shopId)
        .order('display_name');
    return rows
        .map(
          (row) => CashierMetadata(
            id: row['id']! as String,
            displayName: row['display_name']! as String,
            isActive: row['is_active']! as bool,
          ),
        )
        .toList();
  }

  @override
  Future<String> createCashier({
    required String shopId,
    required String displayName,
    required String pin,
  }) async {
    final result = await client.rpc(
      'create_cashier',
      params: {
        'p_shop_id': shopId,
        'p_display_name': displayName,
        'p_login_code': const UuidV7Generator().next(),
        'p_pin': pin,
      },
    );
    return result as String;
  }

  @override
  Future<void> setActive({
    required String shopId,
    required String cashierId,
    required bool isActive,
  }) async {
    await client.rpc(
      'set_cashier_active',
      params: {
        'p_shop_id': shopId,
        'p_cashier_id': cashierId,
        'p_is_active': isActive,
      },
    );
  }
}
