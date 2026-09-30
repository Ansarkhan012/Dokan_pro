import '../../core/domain/enums.dart';

final class RegisteredDevice {
  const RegisteredDevice({required this.id, required this.isActive});
  final String id;
  final bool isActive;
}

abstract interface class DeviceRegistrationGateway {
  Future<RegisteredDevice> register({
    required String shopId,
    required String deviceName,
    required DeviceType type,
    required String identifier,
  });
  Future<RegisteredDevice?> find({
    required String shopId,
    required String identifier,
  });
}
