import 'cashier_session.dart';

abstract interface class CashierAuthGateway {
  Future<CashierSession> authenticate({
    required String shopId,
    required String deviceIdentifier,
    required String cashierId,
    required String pin,
  });
  Future<bool> validate(CashierSession session);
  Future<void> revoke(CashierSession session);
}
