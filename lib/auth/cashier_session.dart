final class CashierSession {
  const CashierSession({
    required this.token,
    required this.shopId,
    required this.cashierId,
    required this.deviceId,
    required this.expiresAt,
  });
  final String token;
  final String shopId;
  final String cashierId;
  final String deviceId;
  final DateTime expiresAt;
  bool isLocallyValidAt(DateTime now) =>
      now.toUtc().isBefore(expiresAt.toUtc());
  Map<String, dynamic> toJson() => {
    'token': token,
    'shop_id': shopId,
    'cashier_id': cashierId,
    'device_id': deviceId,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
  factory CashierSession.fromJson(Map<String, dynamic> json) => CashierSession(
    token: json['token']! as String,
    shopId: json['shop_id']! as String,
    cashierId: json['cashier_id']! as String,
    deviceId: json['device_id']! as String,
    expiresAt: DateTime.parse(json['expires_at']! as String),
  );
}
