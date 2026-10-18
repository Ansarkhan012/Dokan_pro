import 'domain/shop_membership.dart';
import 'shop_bootstrap_gateway.dart';

sealed class ShopBootstrapState {
  const ShopBootstrapState();
}

/// Signed in, but no shop is linked to the account. Only Dokan Pro Support
/// can create and assign a shop.
final class NoShopAssigned extends ShopBootstrapState {
  const NoShopAssigned();
}

final class ShopReady extends ShopBootstrapState {
  const ShopReady(this.membership);
  final ShopMembership membership;
}

final class ShopBootstrapService {
  ShopBootstrapService(this.gateway);
  final ShopBootstrapGateway gateway;
  Future<ShopBootstrapState> resolve() async {
    final memberships = await gateway.memberships();
    return memberships.isEmpty
        ? const NoShopAssigned()
        : ShopReady(memberships.first);
  }
}
