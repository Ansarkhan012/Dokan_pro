import 'domain/shop_membership.dart';

abstract interface class ShopBootstrapGateway {
  Future<List<ShopMembership>> memberships();
  Future<ShopMembership> createOwnerShop({
    required String name,
    required String phone,
    required String address,
  });
}
