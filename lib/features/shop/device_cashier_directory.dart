import 'package:supabase_flutter/supabase_flutter.dart';
import 'cashier_admin_gateway.dart';

/// Cashier list for the device lobby, read with the device credential
/// (`device_pull`). Read-only: cashier administration needs the owner.
final class DeviceCashierDirectory implements CashierAdminGateway {
  DeviceCashierDirectory(this.deviceClient);
  final SupabaseClient deviceClient;

  @override
  Future<List<CashierMetadata>> cashiers({required String shopId}) async {
    final cashiers = <CashierMetadata>[];
    Object? afterSeq;
    Object? afterId;
    while (true) {
      final page =
          await deviceClient.rpc(
                'device_pull',
                params: {
                  'p_entity': 'cashiers',
                  'p_after_seq': afterSeq,
                  'p_after_id': afterId,
                  'p_limit': 500,
                },
              )
              as List<dynamic>;
      for (final value in page) {
        final row = value as Map<String, dynamic>;
        if (row['shop_id'] != shopId) continue;
        cashiers.add(
          CashierMetadata(
            id: row['id']! as String,
            displayName: row['display_name']! as String,
            isActive: row['is_active']! as bool,
          ),
        );
        afterSeq = row['server_seq'];
        afterId = row['id'];
      }
      if (page.length < 500) break;
    }
    return cashiers..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  @override
  Future<String> createCashier({
    required String shopId,
    required String displayName,
    required String pin,
  }) => throw StateError('Only the owner can create cashiers.');

  @override
  Future<void> setActive({
    required String shopId,
    required String cashierId,
    required bool isActive,
  }) => throw StateError('Only the owner can change cashiers.');
}
