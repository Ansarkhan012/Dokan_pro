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
        ? 'id,shop_id,display_name,login_code,credential_version,is_active,created_at,updated_at'
        : '*';
    dynamic query = client.from(table).select(columns);
    if (entity == PullEntity.shops) {
      query = query.eq('id', shopId);
    } else if (entity == PullEntity.categories) {
      query = query.or('shop_id.is.null,shop_id.eq.$shopId');
    } else if (entity != PullEntity.masterProducts &&
        entity != PullEntity.categories) {
      query = query.eq('shop_id', shopId);
    }
    final timestampColumn =
        entity == PullEntity.inventoryMovements ||
            entity == PullEntity.customerLedgerEntries ||
            entity == PullEntity.supplierLedgerEntries ||
            entity == PullEntity.purchases ||
            entity == PullEntity.purchaseItems ||
            entity == PullEntity.purchasePayments ||
            entity == PullEntity.expenses ||
            entity == PullEntity.sales ||
            entity == PullEntity.saleItems ||
            entity == PullEntity.salePayments ||
            entity == PullEntity.saleReturns ||
            entity == PullEntity.saleReturnItems ||
            entity == PullEntity.saleVoids
        ? 'created_at'
        : 'updated_at';
    if (after != null) {
      final stamp = after.updatedAt.toUtc().toIso8601String();
      query = query.or(
        '$timestampColumn.gt.$stamp,and($timestampColumn.eq.$stamp,id.gt.${after.entityId})',
      );
    }
    final rows =
        await query.order(timestampColumn).order('id').limit(limit)
            as List<dynamic>;
    return rows.map((value) {
      final row = value as Map<String, dynamic>;
      return RemoteChange(
        entity: entity,
        id: row['id']! as String,
        shopId: row['shop_id'] as String?,
        updatedAt: DateTime.parse(row[timestampColumn]! as String).toUtc(),
        data: row,
      );
    }).toList();
  }

  String _table(PullEntity entity) => switch (entity) {
    PullEntity.shops => 'shops',
    PullEntity.devices => 'devices',
    PullEntity.cashiers => 'cashiers',
    PullEntity.categories => 'categories',
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
