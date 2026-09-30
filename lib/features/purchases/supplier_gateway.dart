import 'package:supabase_flutter/supabase_flutter.dart';
import 'purchase_models.dart';

final class SupplierGateway {
  SupplierGateway(this.client);
  final SupabaseClient client;
  Future<void> save({
    required String shopId,
    String? supplierId,
    required SupplierInput input,
  }) async {
    await client.rpc(
      'save_supplier',
      params: {
        'p_shop_id': shopId,
        'p_supplier_id': supplierId,
        'p_name': input.name,
        'p_contact_person': input.contactPerson,
        'p_phone': input.phone,
        'p_address': input.address,
        'p_notes': input.notes,
        'p_is_active': input.isActive,
      },
    );
  }
}
