import 'domain/shop_membership.dart';

/// Reads the signed-in user's shops. Shops are created only by Dokan Pro
/// Support (admin_create_shop on the server); the app never creates one.
abstract interface class ShopBootstrapGateway {
  Future<List<ShopMembership>> memberships();
}
