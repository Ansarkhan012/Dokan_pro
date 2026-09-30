import 'dart:convert';

import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../database/app_database.dart';
import 'pull_models.dart';
import 'reference_pull_gateway.dart';

final class ReferencePullService {
  ReferencePullService(this.db, this.gateway, {required this.shopId});
  final AppDatabase db;
  final ReferencePullGateway gateway;
  final String shopId;

  Future<int> pull(PullEntity entity, {int pageSize = 100}) async {
    var applied = 0;
    while (true) {
      final cursor = await _cursor(entity);
      final changes = await gateway.fetch(
        entity: entity,
        shopId: shopId,
        after: cursor,
        limit: pageSize,
      );
      if (changes.isEmpty) return applied;
      await db.transaction(() async {
        for (final change in changes) {
          _validateTenant(change);
          await _apply(change);
          await db
              .into(db.syncCursors)
              .insertOnConflictUpdate(
                SyncCursorsCompanion.insert(
                  shopId: shopId,
                  entityType: entity.name,
                  updatedAt: change.updatedAt,
                  entityId: change.id,
                ),
              );
          applied++;
        }
      });
      if (changes.length < pageSize) return applied;
    }
  }

  Future<PullCursor?> _cursor(PullEntity entity) async {
    final row =
        await (db.select(db.syncCursors)..where(
              (t) => t.shopId.equals(shopId) & t.entityType.equals(entity.name),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : PullCursor(updatedAt: row.updatedAt, entityId: row.entityId);
  }

  void _validateTenant(RemoteChange change) {
    if (change.entity == PullEntity.masterProducts) return;
    if (change.entity == PullEntity.categories && change.shopId == null) return;
    if (change.entity == PullEntity.shops) {
      if (change.id != shopId) throw StateError('Foreign shop pull rejected');
      return;
    }
    if (change.shopId != shopId) {
      throw StateError('Foreign tenant pull rejected');
    }
  }

  DateTime _date(Map<String, dynamic> row, String key) =>
      DateTime.parse(row[key]! as String).toUtc();
  Value<String?> _text(Map<String, dynamic> row, String key) =>
      Value(row[key] as String?);
  Future<void> _apply(RemoteChange c) async {
    final r = c.data;
    switch (c.entity) {
      case PullEntity.shops:
        await db
            .into(db.shops)
            .insertOnConflictUpdate(
              ShopsCompanion.insert(
                id: c.id,
                name: r['name']! as String,
                phone: r['phone']! as String,
                address: r['address']! as String,
                currency: Value(r['currency']! as String),
                timezone: Value(r['timezone']! as String),
                subscriptionPlan: SubscriptionPlan.values.byName(
                  r['subscription_plan']! as String,
                ),
                subscriptionStatus: SubscriptionStatus.values.byName(
                  r['subscription_status']! as String,
                ),
                allowNegativeStock: Value(r['allow_negative_stock']! as bool),
                defaultLowStockLevel: Value(
                  (r['default_low_stock_level'] as num?)?.toInt() ?? 0,
                ),
                receiptFooter: Value(r['receipt_footer'] as String? ?? ''),
                receiptPaperWidth: Value(
                  r['receipt_paper_width'] as String? ?? '80mm',
                ),
                receiptShowPhone: Value(
                  r['receipt_show_phone'] as bool? ?? true,
                ),
                receiptShowAddress: Value(
                  r['receipt_show_address'] as bool? ?? true,
                ),
                notificationsEnabled: Value(
                  r['notifications_enabled'] as bool? ?? false,
                ),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.devices:
        await db
            .into(db.devices)
            .insertOnConflictUpdate(
              DevicesCompanion.insert(
                id: c.id,
                shopId: shopId,
                deviceName: r['device_name']! as String,
                deviceType: DeviceType.values.byName(
                  r['device_type']! as String,
                ),
                deviceIdentifier: r['device_identifier']! as String,
                isActive: Value(r['is_active']! as bool),
                lastSeenAt: Value(
                  r['last_seen_at'] == null ? null : _date(r, 'last_seen_at'),
                ),
                lastSyncedAt: Value(
                  r['last_synced_at'] == null
                      ? null
                      : _date(r, 'last_synced_at'),
                ),
                createdAt: _date(r, 'created_at'),
                updatedAt: Value(c.updatedAt),
              ),
            );
      case PullEntity.cashiers:
        if (r.containsKey('pin_hash')) {
          throw StateError('Cashier secret entered pull response');
        }
        await db
            .into(db.cashiers)
            .insertOnConflictUpdate(
              CashiersCompanion.insert(
                id: c.id,
                shopId: shopId,
                displayName: r['display_name']! as String,
                loginCode: r['login_code']! as String,
                credentialVersion: Value(r['credential_version']! as int),
                isActive: Value(r['is_active']! as bool),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.categories:
        await db
            .into(db.categories)
            .insertOnConflictUpdate(
              CategoriesCompanion.insert(
                id: c.id,
                shopId: Value(c.shopId),
                name: r['name']! as String,
                isActive: Value(r['is_active']! as bool),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.masterProducts:
        await db
            .into(db.masterProducts)
            .insertOnConflictUpdate(
              MasterProductsCompanion.insert(
                id: c.id,
                barcode: r['barcode']! as String,
                name: r['name']! as String,
                brand: r['brand']! as String,
                categoryId: _text(r, 'category_id'),
                defaultImagePath: _text(r, 'default_image_path'),
                defaultUnit: r['default_unit']! as String,
                packLabel: _text(r, 'pack_label'),
                isActive: Value(r['is_active']! as bool),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.shopProducts:
        await db
            .into(db.shopProducts)
            .insertOnConflictUpdate(
              ShopProductsCompanion.insert(
                id: c.id,
                shopId: shopId,
                masterProductId: _text(r, 'master_product_id'),
                customName: _text(r, 'custom_name'),
                barcode: _text(r, 'barcode'),
                categoryId: _text(r, 'category_id'),
                unit: _text(r, 'unit'),
                packLabel: _text(r, 'pack_label'),
                imagePath: _text(r, 'image_path'),
                purchasePrice: r['purchase_price']! as int,
                salePrice: r['sale_price']! as int,
                stockTrackingEnabled: Value(
                  r['stock_tracking_enabled']! as bool,
                ),
                lowStockLevel: Value(r['low_stock_level'] as int?),
                isActive: Value(r['is_active']! as bool),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.customers:
        await db
            .into(db.customers)
            .insertOnConflictUpdate(
              CustomersCompanion.insert(
                id: c.id,
                shopId: shopId,
                name: r['name']! as String,
                phone: _text(r, 'phone'),
                address: _text(r, 'address'),
                notes: _text(r, 'notes'),
                creditLimit: Value(r['credit_limit'] as int?),
                isActive: Value(r['is_active']! as bool),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.customerLedgerEntries:
        await db
            .into(db.customerLedgerEntries)
            .insertOnConflictUpdate(
              CustomerLedgerEntriesCompanion.insert(
                id: c.id,
                shopId: shopId,
                customerId: r['customer_id']! as String,
                type: CustomerLedgerType.values.byName(r['type']! as String),
                amount: r['amount']! as int,
                saleId: _text(r, 'sale_id'),
                paymentReference: _text(r, 'payment_reference'),
                paymentMethod: _text(r, 'payment_method'),
                note: _text(r, 'note'),
                createdBy: r['created_by']! as String,
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.suppliers:
        await db
            .into(db.suppliers)
            .insertOnConflictUpdate(
              SuppliersCompanion.insert(
                id: c.id,
                shopId: shopId,
                name: r['name']! as String,
                contactPerson: _text(r, 'contact_person'),
                phone: _text(r, 'phone'),
                address: _text(r, 'address'),
                notes: _text(r, 'notes'),
                isActive: Value(r['is_active']! as bool),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.supplierLedgerEntries:
        await db
            .into(db.supplierLedgerEntries)
            .insertOnConflictUpdate(
              SupplierLedgerEntriesCompanion.insert(
                id: c.id,
                shopId: shopId,
                supplierId: r['supplier_id']! as String,
                type: SupplierLedgerType.values.byName(r['type']! as String),
                amount: r['amount']! as int,
                purchaseId: _text(r, 'purchase_id'),
                paymentReference: _text(r, 'payment_reference'),
                paymentMethod: _text(r, 'payment_method'),
                note: _text(r, 'note'),
                createdBy: r['created_by']! as String,
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.purchases:
        await db
            .into(db.purchases)
            .insertOnConflictUpdate(
              PurchasesCompanion.insert(
                id: c.id,
                shopId: shopId,
                supplierId: Value(r['supplier_id']! as String),
                deviceId: _text(r, 'device_id'),
                invoiceNumber: _text(r, 'invoice_number'),
                notes: _text(r, 'notes'),
                subtotal: r['subtotal']! as int,
                discountTotal: r['discount_total']! as int,
                total: r['total']! as int,
                paidAmount: Value(r['paid_amount']! as int),
                paymentStatus: PaymentStatus.values.byName(
                  r['payment_status']! as String,
                ),
                createdBy: r['created_by']! as String,
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.purchaseItems:
        await db
            .into(db.purchaseItems)
            .insertOnConflictUpdate(
              PurchaseItemsCompanion.insert(
                id: c.id,
                shopId: shopId,
                purchaseId: r['purchase_id']! as String,
                productId: r['product_id']! as String,
                productNameSnapshot: Value(
                  r['product_name_snapshot']! as String,
                ),
                quantity: r['quantity']! as int,
                unitCost: r['unit_cost']! as int,
                lineTotal: r['line_total']! as int,
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.purchasePayments:
        await db
            .into(db.purchasePayments)
            .insertOnConflictUpdate(
              PurchasePaymentsCompanion.insert(
                id: c.id,
                shopId: shopId,
                purchaseId: r['purchase_id']! as String,
                paymentMethod: PaymentMethod.values.byName(
                  r['payment_method']! as String,
                ),
                amount: r['amount']! as int,
                reference: _text(r, 'reference'),
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.expenseCategories:
        await db
            .into(db.expenseCategories)
            .insertOnConflictUpdate(
              ExpenseCategoriesCompanion.insert(
                id: c.id,
                shopId: shopId,
                name: r['name']! as String,
                isActive: Value(r['is_active']! as bool),
                createdAt: _date(r, 'created_at'),
                updatedAt: c.updatedAt,
              ),
            );
      case PullEntity.expenses:
        await db
            .into(db.expenses)
            .insertOnConflictUpdate(
              ExpensesCompanion.insert(
                id: c.id,
                shopId: shopId,
                category: r['category']! as String,
                categoryId: _text(r, 'category_id'),
                amount: r['amount']! as int,
                paymentMethod: Value(
                  PaymentMethod.values.byName(r['payment_method']! as String),
                ),
                description: _text(r, 'description'),
                note: _text(r, 'note'),
                reference: _text(r, 'reference'),
                deviceId: _text(r, 'device_id'),
                expenseAt: Value(_date(r, 'expense_at')),
                createdBy: r['created_by']! as String,
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.inventoryMovements:
        await db
            .into(db.inventoryMovements)
            .insertOnConflictUpdate(
              InventoryMovementsCompanion.insert(
                id: c.id,
                shopId: shopId,
                productId: r['product_id']! as String,
                type: InventoryMovementType.values.byName(r['type']! as String),
                quantity: r['quantity']! as int,
                referenceType: _text(r, 'reference_type'),
                referenceId: _text(r, 'reference_id'),
                note: _text(r, 'note'),
                createdBy: r['created_by']! as String,
                deviceId: _text(r, 'device_id'),
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.sales:
        await db
            .into(db.sales)
            .insertOnConflictUpdate(
              SalesCompanion.insert(
                id: c.id,
                shopId: shopId,
                cashierId: r['cashier_id']! as String,
                customerId: _text(r, 'customer_id'),
                deviceId: r['device_id']! as String,
                invoiceNumber: _text(r, 'invoice_number'),
                subtotal: r['subtotal']! as int,
                discountTotal: r['discount_total']! as int,
                taxTotal: r['tax_total']! as int,
                grandTotal: r['grand_total']! as int,
                paymentStatus: PaymentStatus.values.byName(
                  r['payment_status']! as String,
                ),
                saleStatus: SaleStatus.values.byName(
                  r['sale_status']! as String,
                ),
                createdAt: _date(r, 'created_at'),
                syncedAt: Value(
                  r['synced_at'] == null ? null : _date(r, 'synced_at'),
                ),
              ),
            );
      case PullEntity.saleItems:
        await db
            .into(db.saleItems)
            .insertOnConflictUpdate(
              SaleItemsCompanion.insert(
                id: c.id,
                shopId: shopId,
                saleId: r['sale_id']! as String,
                productId: r['product_id']! as String,
                productNameSnapshot: r['product_name_snapshot']! as String,
                barcodeSnapshot: _text(r, 'barcode_snapshot'),
                quantity: r['quantity']! as int,
                costPriceSnapshot: r['cost_price_snapshot']! as int,
                salePriceSnapshot: r['sale_price_snapshot']! as int,
                discountAmount: r['discount_amount']! as int,
                lineTotal: r['line_total']! as int,
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.salePayments:
        await db
            .into(db.salePayments)
            .insertOnConflictUpdate(
              SalePaymentsCompanion.insert(
                id: c.id,
                shopId: shopId,
                saleId: r['sale_id']! as String,
                paymentMethod: PaymentMethod.values.byName(
                  r['payment_method']! as String,
                ),
                amount: r['amount']! as int,
                reference: _text(r, 'reference'),
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.saleReturns:
        await db
            .into(db.saleReturns)
            .insertOnConflictUpdate(
              SaleReturnsCompanion.insert(
                id: c.id,
                shopId: shopId,
                originalSaleId: r['original_sale_id']! as String,
                customerId: _text(r, 'customer_id'),
                deviceId: r['device_id']! as String,
                refundMethod: PaymentMethod.values.byName(
                  r['refund_method']! as String,
                ),
                refundAmount: r['refund_amount']! as int,
                reason: r['reason']! as String,
                createdBy: r['created_by']! as String,
                createdAt: _date(r, 'created_at'),
                syncedAt: Value(
                  r['synced_at'] == null ? null : _date(r, 'synced_at'),
                ),
              ),
            );
      case PullEntity.saleReturnItems:
        await db
            .into(db.saleReturnItems)
            .insertOnConflictUpdate(
              SaleReturnItemsCompanion.insert(
                id: c.id,
                shopId: shopId,
                returnId: r['return_id']! as String,
                originalSaleItemId: r['original_sale_item_id']! as String,
                productId: r['product_id']! as String,
                productNameSnapshot: r['product_name_snapshot']! as String,
                quantity: r['quantity']! as int,
                unitPriceSnapshot: r['unit_price_snapshot']! as int,
                refundAmount: r['refund_amount']! as int,
                createdAt: _date(r, 'created_at'),
              ),
            );
      case PullEntity.saleVoids:
        await db
            .into(db.saleVoids)
            .insertOnConflictUpdate(
              SaleVoidsCompanion.insert(
                id: c.id,
                shopId: shopId,
                originalSaleId: r['original_sale_id']! as String,
                deviceId: r['device_id']! as String,
                amount: r['amount']! as int,
                reason: r['reason']! as String,
                paymentBreakdown: jsonEncode(r['payment_breakdown']),
                createdBy: r['created_by']! as String,
                createdAt: _date(r, 'created_at'),
                syncedAt: Value(
                  r['synced_at'] == null ? null : _date(r, 'synced_at'),
                ),
              ),
            );
    }
  }
}
