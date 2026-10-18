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
    final isActive = row['is_active']! as bool;
    return RegisteredDevice(
      id: row['device_id']! as String,
      isActive: isActive,
      approvalStatus:
          row['approval_status'] as String? ??
          (isActive ? 'approved' : 'revoked'),
    );
  }

  @override
  Future<RegisteredDevice?> find({
    required String shopId,
    required String identifier,
  }) async {
    Future<Map<String, dynamic>?> select(String columns) => client
        .from('devices')
        .select(columns)
        .eq('shop_id', shopId)
        .eq('device_identifier', identifier)
        .maybeSingle();
    Map<String, dynamic>? row;
    try {
      row = await select('id,is_active,approval_status');
    } on PostgrestException catch (e) {
      // 42703: a server without migration 202610140001 has no such column.
      if (e.code != '42703') rethrow;
      row = await select('id,is_active');
    }
    if (row == null) return null;
    final isActive = row['is_active']! as bool;
    return RegisteredDevice(
      id: row['id']! as String,
      isActive: isActive,
      approvalStatus:
          row['approval_status'] as String? ??
          (isActive ? 'approved' : 'revoked'),
    );
  }
}
