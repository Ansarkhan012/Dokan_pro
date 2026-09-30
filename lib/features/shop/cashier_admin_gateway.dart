final class CashierMetadata {
  const CashierMetadata({
    required this.id,
    required this.displayName,
    required this.isActive,
  });

  final String id;
  final String displayName;
  final bool isActive;
}

abstract interface class CashierAdminGateway {
  Future<List<CashierMetadata>> cashiers({required String shopId});

  Future<String> createCashier({
    required String shopId,
    required String displayName,
    required String pin,
  });
  Future<void> setActive({
    required String shopId,
    required String cashierId,
    required bool isActive,
  });
}
