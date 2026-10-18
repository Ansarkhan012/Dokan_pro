import 'package:supabase_flutter/supabase_flutter.dart';
import 'pull_models.dart';
import 'reference_pull_gateway.dart';

final class SupabaseReferencePullGateway implements ReferencePullGateway {
  SupabaseReferencePullGateway(this.client);
  final SupabaseClient client;
  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    final table = _table(entity);
    final columns = entity == PullEntity.cashiers
        ? 'id,shop_id,display_name,login_code,credential_version,is_active,created_at,updated_at,server_seq'
        : '*';
    dynamic query = client.from(table).select(columns);
    if (entity == PullEntity.shops) {
      query = query.eq('id', shopId);
    } else if (entity == PullEntity.globalCategories) {
      query = query.isFilter('shop_id', null);
    } else if (entity != PullEntity.masterProducts) {
      query = query.eq('shop_id', shopId);
    }
    // R1.4: the server-assigned (server_seq, id) is the only position; the
    // client's clock and the timestamp precision play no part in paging.
    if (after != null && after.serverSeq >= 0) {
      final seq = after.serverSeq;
      query = after.entityId.isEmpty
          ? query.gt('server_seq', seq)
          : query.or(
              'server_seq.gt.$seq,and(server_seq.eq.$seq,id.gt.${after.entityId})',
            );
    }
    final rows =
        await query.order('server_seq').order('id').limit(limit)
            as List<dynamic>;
    return rows
        .map((value) => remoteChangeFrom(entity, value as Map<String, dynamic>))
        .toList();
  }

  String _table(PullEntity entity) => switch (entity) {
    PullEntity.shops => 'shops',
    PullEntity.devices => 'devices',
    PullEntity.cashiers => 'cashiers',
    PullEntity.categories || PullEntity.globalCategories => 'categories',
    PullEntity.masterProducts => 'master_products',
    PullEntity.shopProducts => 'shop_products',
    PullEntity.customers => 'customers',
    PullEntity.customerLedgerEntries => 'customer_ledger_entries',
    PullEntity.suppliers => 'suppliers',
    PullEntity.supplierLedgerEntries => 'supplier_ledger_entries',
    PullEntity.purchases => 'purchases',
    PullEntity.purchaseItems => 'purchase_items',
    PullEntity.purchasePayments => 'purchase_payments',
    PullEntity.expenseCategories => 'expense_categories',
    PullEntity.expenses => 'expenses',
    PullEntity.inventoryMovements => 'inventory_movements',
    PullEntity.sales => 'sales',
    PullEntity.saleItems => 'sale_items',
    PullEntity.salePayments => 'sale_payments',
    PullEntity.saleReturns => 'sale_returns',
    PullEntity.saleReturnItems => 'sale_return_items',
    PullEntity.saleVoids => 'sale_voids',
  };
}

/// Cashier-mode pull through the session-less device client: the server's
/// `device_pull` returns the credential's own shop only, with the same R1.4
/// (server_seq, id) order and strictly-after cursor as the owner pull.
final class DeviceReferencePullGateway implements ReferencePullGateway {
  DeviceReferencePullGateway(this.deviceClient);
  final SupabaseClient deviceClient;

  /// The entities cashier mode pulls; device_pull refuses every other one.
  static const supported = {
    PullEntity.shops,
    PullEntity.devices,
    PullEntity.cashiers,
    PullEntity.categories,
    PullEntity.globalCategories,
    PullEntity.masterProducts,
    PullEntity.shopProducts,
    PullEntity.customers,
    PullEntity.customerLedgerEntries,
    PullEntity.inventoryMovements,
    PullEntity.sales,
    PullEntity.saleItems,
    PullEntity.salePayments,
    PullEntity.saleReturns,
    PullEntity.saleReturnItems,
    PullEntity.saleVoids,
  };

  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    if (!supported.contains(entity)) {
      throw UnsupportedError('Cashier mode does not pull ${entity.name}.');
    }
    final positioned = after != null && after.serverSeq >= 0;
    final rows =
        await deviceClient.rpc(
              'device_pull',
              params: {
                'p_entity': entity.name,
                'p_after_seq': positioned ? after.serverSeq : null,
                'p_after_id': positioned && after.entityId.isNotEmpty
                    ? after.entityId
                    : null,
                'p_limit': limit,
              },
            )
            as List<dynamic>;
    return rows
        .map((value) => remoteChangeFrom(entity, value as Map<String, dynamic>))
        .toList();
  }
}

/// One pulled row as a change; immutable history is timed by created_at.
RemoteChange remoteChangeFrom(PullEntity entity, Map<String, dynamic> row) =>
    RemoteChange(
      entity: entity,
      id: row['id']! as String,
      shopId: row['shop_id'] as String?,
      updatedAt: DateTime.parse(
        row[_createdAtEntities.contains(entity) ? 'created_at' : 'updated_at']!
            as String,
      ).toUtc(),
      serverSeq: (row['server_seq']! as num).toInt(),
      data: row,
    );

const _createdAtEntities = {
  PullEntity.inventoryMovements,
  PullEntity.customerLedgerEntries,
  PullEntity.supplierLedgerEntries,
  PullEntity.purchases,
  PullEntity.purchaseItems,
  PullEntity.purchasePayments,
  PullEntity.expenses,
  PullEntity.sales,
  PullEntity.saleItems,
  PullEntity.salePayments,
  PullEntity.saleReturns,
  PullEntity.saleReturnItems,
  PullEntity.saleVoids,
};
