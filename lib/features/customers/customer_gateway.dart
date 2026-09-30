import 'customer_models.dart';

abstract interface class CustomerGateway {
  Future<void> saveCustomer({
    required String shopId,
    String? customerId,
    required CustomerInput input,
  });
}
