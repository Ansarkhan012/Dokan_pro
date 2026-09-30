import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import 'device_registration_gateway.dart';

final class SupabaseDeviceRegistrationGateway
    implements DeviceRegistrationGateway {
  SupabaseDeviceRegistrationGateway(this.client);
  final SupabaseClient client;
  @override
  Future<RegisteredDevice> register({
    required String shopId,
    required String deviceName,
    required DeviceType type,
    required String identifier,
  }) async {
    final result = await client.rpc(
      'register_shop_device',
      params: {
        'p_shop_id': shopId,
        'p_device_name': deviceName,
        'p_device_type': type.name,
        'p_device_identifier': identifier,
      },
    );
    final row = (result as List<dynamic>).single as Map<String, dynamic>;
    return RegisteredDevice(
      id: row['device_id']! as String,
      isActive: row['is_active']! as bool,
    );
  }

  @override
  Future<RegisteredDevice?> find({
    required String shopId,
    required String identifier,
  }) async {
    final row = await client
        .from('devices')
        .select('id,is_active')
        .eq('shop_id', shopId)
        .eq('device_identifier', identifier)
        .maybeSingle();
    if (row == null) return null;
    return RegisteredDevice(
      id: row['id']! as String,
      isActive: row['is_active']! as bool,
    );
  }
}
