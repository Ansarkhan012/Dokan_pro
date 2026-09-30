import '../../../core/domain/enums.dart';

final class ShopMembership {
  const ShopMembership({
    required this.shopId,
    required this.shopName,
    required this.role,
  });
  final String shopId;
  final String shopName;
  final ShopRole role;
}
