import 'package:supabase_flutter/supabase_flutter.dart';
import 'sale_upload_gateway.dart';
import 'sale_payload_codec.dart';

final class SupabaseSaleUploadGateway implements SaleUploadGateway {
  SupabaseSaleUploadGateway(this.client);
  final SupabaseClient client;
  @override
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) async {
    final operation = payload['operation'];
    final rpc = switch (operation) {
      'sync_customer_payment' => 'sync_customer_payment',
      'sync_purchase_transaction' => 'sync_purchase_transaction',
      'sync_supplier_payment' => 'sync_supplier_payment',
      'sync_expense' => 'sync_expense',
      'sync_inventory_adjustment' => 'sync_inventory_adjustment',
      'sync_sale_return' => 'sync_sale_return',
      'sync_sale_void' => 'sync_sale_void',
      _ => 'sync_sale_transaction',
    };
    await client.rpc(
      rpc,
      params: {
        'p_payload': payloadForCloud(payload),
        'p_cashier_token': cashierSessionToken,
      },
    );
  }
}
