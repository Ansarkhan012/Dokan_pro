import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import 'domain/shop_membership.dart';
import 'shop_bootstrap_gateway.dart';

final class SupabaseShopBootstrapGateway implements ShopBootstrapGateway {
  SupabaseShopBootstrapGateway(this.client);
  final SupabaseClient client;
  @override
  Future<List<ShopMembership>> memberships() async {
    final rows = await client
        .from('shop_users')
        .select('shop_id, role, shops(name)')
        .eq('is_active', true);
    return rows.map((row) {
      final shop = row['shops']! as Map<String, dynamic>;
      return ShopMembership(
        shopId: row['shop_id']! as String,
        shopName: shop['name']! as String,
        role: ShopRole.values.byName(row['role']! as String),
      );
    }).toList();
  }
}
