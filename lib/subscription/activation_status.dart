import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/l10n/l10n.dart';

/// Shop licence as decided by Dokan Pro Support (shops.license_status).
enum ShopLicense { pending, active, suspended, unknown }

/// This device's decision under the two-device rule (devices.approval_status).
enum DeviceApproval { approved, pending, rejected, revoked, unknown }

ShopLicense shopLicenseFrom(Object? value) => switch (value) {
  'pending' => ShopLicense.pending,
  'active' => ShopLicense.active,
  'suspended' => ShopLicense.suspended,
  _ => ShopLicense.unknown,
};

DeviceApproval deviceApprovalFrom(Object? value) => switch (value) {
  'approved' => DeviceApproval.approved,
  'pending' => DeviceApproval.pending,
  'rejected' => DeviceApproval.rejected,
  'revoked' => DeviceApproval.revoked,
  _ => DeviceApproval.unknown,
};

/// What the owner screen shows about licensing. Display only: billing is
/// decided offline by the signed entitlement (EntitlementPolicyService), never
/// by this online read.
final class ActivationStatus {
  const ActivationStatus({
    required this.license,
    required this.deviceApproval,
    this.planId,
    this.periodEnd,
    this.graceUntil,
    this.serverTime,
  });
  final ShopLicense license;
  final DeviceApproval deviceApproval;
  final String? planId;
  final DateTime? periodEnd, graceUntil, serverTime;

  bool get subscriptionEnded {
    final end = periodEnd;
    return end != null && end.isBefore(serverTime ?? DateTime.now().toUtc());
  }

  factory ActivationStatus.fromJson(Map<String, dynamic> j) {
    DateTime? time(String key) =>
        j[key] is String ? DateTime.tryParse(j[key] as String)?.toUtc() : null;
    return ActivationStatus(
      license: shopLicenseFrom(j['license_status']),
      deviceApproval: deviceApprovalFrom(j['device_approval_status']),
      planId: j['plan_id'] as String?,
      periodEnd: time('period_end'),
      graceUntil: time('grace_until'),
      serverTime: time('server_time'),
    );
  }
}

abstract interface class ActivationStatusGateway {
  /// Null when the server does not offer the status (not yet migrated).
  Future<ActivationStatus?> load({
    required String shopId,
    required String deviceIdentifier,
  });
}

final class SupabaseActivationStatusGateway implements ActivationStatusGateway {
  const SupabaseActivationStatusGateway(this.client);
  final SupabaseClient client;

  @override
  Future<ActivationStatus?> load({
    required String shopId,
    required String deviceIdentifier,
  }) async {
    try {
      final raw = await client.rpc(
        'owner_activation_status',
        params: {'p_shop_id': shopId, 'p_device_identifier': deviceIdentifier},
      );
      return raw is Map
          ? ActivationStatus.fromJson(Map<String, dynamic>.from(raw))
          : null;
    } on PostgrestException catch (e) {
      // PGRST202: function missing on a server without migration 202610140001.
      if (e.code == 'PGRST202') return null;
      rethrow;
    }
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// Licence and subscription summary for the owner's device screen.
class ActivationStatusPanel extends StatelessWidget {
  const ActivationStatusPanel({super.key, required this.status});
  final ActivationStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (String licence, Color color) = switch (status.license) {
      ShopLicense.active => (l10n.activationShopActive, scheme.primary),
      ShopLicense.pending => (l10n.activationShopPending, scheme.tertiary),
      ShopLicense.suspended => (l10n.activationShopSuspended, scheme.error),
      ShopLicense.unknown => (l10n.activationContactSupport, scheme.outline),
    };
    final end = status.periodEnd;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              licence,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            if (end != null)
              Text(
                status.subscriptionEnded
                    ? l10n.activationExpiredOn(_date(end))
                    : l10n.activationValidUntil(_date(end)),
                style: status.subscriptionEnded
                    ? TextStyle(color: scheme.error)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
