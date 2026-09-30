abstract interface class SaleUploadGateway {
  Future<void> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  });
}
