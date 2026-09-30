import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_gateway.dart';
import 'customer_models.dart';

final class SupabaseCustomerGateway implements CustomerGateway {
  SupabaseCustomerGateway(this.client);
  final SupabaseClient client;
  @override
  Future<void> saveCustomer({
    required String shopId,
    String? customerId,
    required CustomerInput input,
  }) async {
    await client.rpc(
      'save_customer',
      params: {
        'p_shop_id': shopId,
        'p_customer_id': customerId,
        'p_name': input.name,
        'p_phone': input.phone,
        'p_address': input.address,
        'p_notes': input.notes,
        'p_credit_limit': input.creditLimitMinor,
        'p_is_active': input.isActive,
      },
    );
  }
}
