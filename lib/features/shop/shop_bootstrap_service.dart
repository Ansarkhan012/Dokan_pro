import 'domain/shop_membership.dart';
import 'shop_bootstrap_gateway.dart';

sealed class ShopBootstrapState {
  const ShopBootstrapState();
}

final class NeedsShopCreation extends ShopBootstrapState {
  const NeedsShopCreation();
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
        ? const NeedsShopCreation()
        : ShopReady(memberships.first);
  }
}
