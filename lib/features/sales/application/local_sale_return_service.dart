import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/domain/enums.dart';
import '../../../core/ids/id_generator.dart';
import '../../../database/app_database.dart';
import '../../../subscription/entitlement_policy.dart';
import '../domain/sale_return.dart';

final class LocalSaleReturnService {
  LocalSaleReturnService(
    this.db,
    this.ids, {
    DateTime Function()? clock,
    this._authorizer = const AllowFinancialMutations(),
  }) : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final IdGenerator ids;
  final DateTime Function() _clock;
  final FinancialMutationAuthorizer _authorizer;

  Future<CreatedSaleReturn> create(SaleReturnDraft draft) async {
    await _authorizer.authorize(shopId: draft.shopId, deviceId: draft.deviceId);
    return db.transaction(() async {
      if (draft.lines.isEmpty) {
        throw ArgumentError('Select at least one item.');
      }
      if (draft.reason.trim().isEmpty) {
        throw ArgumentError('Return reason is required.');
      }
      final owner =
          await (db.select(db.shopUsers)..where(
                (t) =>
                    t.shopId.equals(draft.shopId) &
                    t.userId.equals(draft.ownerId) &
                    t.role.equals(ShopRole.owner.name) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (owner == null) {
        throw StateError('Active owner required.');
      }
      final device =
          await (db.select(db.devices)..where(
                (t) =>
                    t.id.equals(draft.deviceId) &
                    t.shopId.equals(draft.shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (device == null) {
        throw StateError('Active device required.');
      }
      final sale =
          await (db.select(db.sales)..where(
                (t) =>
                    t.id.equals(draft.originalSaleId) &
                    t.shopId.equals(draft.shopId),
              ))
              .getSingleOrNull();
      if (sale == null) {
        throw StateError('Original sale not found.');
      }
      if (await (db.select(db.saleVoids)..where(
                (t) =>
                    t.shopId.equals(draft.shopId) &
                    t.originalSaleId.equals(sale.id),
              ))
              .getSingleOrNull() !=
          null) {
        throw StateError('Voided sale cannot be returned.');
      }
      if (draft.refundMethod == PaymentMethod.credit &&
          sale.customerId == null) {
        throw StateError('Credit refund requires the original customer.');
      }
      final now = _clock().toUtc(),
          returnId = ids.next(),
          auditId = ids.next(),
          operationId = ids.next();
      final payloadItems = <Map<String, Object?>>[],
          payloadMovements = <Map<String, Object?>>[];
      var total = 0;
      for (final line in draft.lines) {
        final item =
            await (db.select(db.saleItems)..where(
                  (t) =>
                      t.id.equals(line.originalSaleItemId) &
                      t.saleId.equals(sale.id) &
                      t.shopId.equals(draft.shopId),
                ))
                .getSingleOrNull();
        if (item == null || line.quantity <= 0) {
          throw StateError('Invalid sale item or quantity.');
        }
        final prior = await db
            .customSelect(
              'select coalesce(sum(ri.quantity),0) q from sale_return_items ri join sale_returns r on r.id=ri.return_id and r.shop_id=ri.shop_id where ri.shop_id=? and r.original_sale_id=? and ri.original_sale_item_id=?',
              variables: [
                Variable(draft.shopId),
                Variable(sale.id),
                Variable(item.id),
              ],
            )
            .getSingle();
        if (prior.read<int>('q') + line.quantity > item.quantity) {
          throw StateError('Return quantity exceeds quantity sold.');
        }
        final refund = line.quantity == item.quantity
            ? item.lineTotal
            : (item.lineTotal * line.quantity + item.quantity ~/ 2) ~/
                  item.quantity;
        final returnItemId = ids.next(), movementId = ids.next();
        total += refund;
        payloadItems.add({
          'id': returnItemId,
          'original_sale_item_id': item.id,
          'product_id': item.productId,
          'product_name_snapshot': item.productNameSnapshot,
          'quantity': line.quantity,
          'unit_price_snapshot': item.salePriceSnapshot,
          'refund_amount': refund,
        });
        payloadMovements.add({
          'id': movementId,
          'product_id': item.productId,
          'type': 'returnIn',
          'quantity': line.quantity,
        });
      }
      if (total <= 0) throw StateError('Return amount must be positive.');
      await db
          .into(db.saleReturns)
          .insert(
            SaleReturnsCompanion.insert(
              id: returnId,
              shopId: draft.shopId,
              originalSaleId: sale.id,
              customerId: Value(sale.customerId),
              deviceId: draft.deviceId,
              refundMethod: draft.refundMethod,
              refundAmount: total,
              reason: draft.reason.trim(),
              createdBy: draft.ownerId,
              createdAt: now,
            ),
          );
      for (var index = 0; index < payloadItems.length; index++) {
        final item = payloadItems[index], movement = payloadMovements[index];
        await db
            .into(db.saleReturnItems)
            .insert(
              SaleReturnItemsCompanion.insert(
                id: item['id']! as String,
                shopId: draft.shopId,
                returnId: returnId,
                originalSaleItemId: item['original_sale_item_id']! as String,
                productId: item['product_id']! as String,
                productNameSnapshot: item['product_name_snapshot']! as String,
                quantity: item['quantity']! as int,
                unitPriceSnapshot: item['unit_price_snapshot']! as int,
                refundAmount: item['refund_amount']! as int,
                createdAt: now,
              ),
            );
        await db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: movement['id']! as String,
                shopId: draft.shopId,
                productId: movement['product_id']! as String,
                type: InventoryMovementType.returnIn,
                quantity: movement['quantity']! as int,
                referenceType: const Value('sale_return'),
                referenceId: Value(returnId),
                note: Value(draft.reason.trim()),
                createdBy: draft.ownerId,
                deviceId: Value(draft.deviceId),
                createdAt: now,
              ),
            );
      }
      String? ledgerId;
      if (draft.refundMethod == PaymentMethod.credit) {
        ledgerId = ids.next();
        await db
            .into(db.customerLedgerEntries)
            .insert(
              CustomerLedgerEntriesCompanion.insert(
                id: ledgerId,
                shopId: draft.shopId,
                customerId: sale.customerId!,
                type: CustomerLedgerType.refund,
                amount: total,
                saleId: Value(sale.id),
                note: Value(draft.reason.trim()),
                createdBy: draft.ownerId,
                createdAt: now,
              ),
            );
      }
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: auditId,
              shopId: draft.shopId,
              userId: draft.ownerId,
              action: 'sale.returned',
              entityType: 'sale_return',
              entityId: returnId,
              newValue: Value(
                jsonEncode({'sale_id': sale.id, 'amount': total}),
              ),
              deviceId: Value(draft.deviceId),
              createdAt: now,
            ),
          );
      final payload = {
        'version': 1,
        'operation': 'sync_sale_return',
        'return': {
          'id': returnId,
          'shop_id': draft.shopId,
          'original_sale_id': sale.id,
          'device_id': draft.deviceId,
          'refund_method': draft.refundMethod.name,
          'refund_amount': total,
          'reason': draft.reason.trim(),
          'created_by': draft.ownerId,
          'created_at': now.toIso8601String(),
        },
        'items': payloadItems,
        'inventory_movements': payloadMovements,
        'ledger_id': ledgerId,
        'audit_id': auditId,
      };
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operationId,
              shopId: draft.shopId,
              deviceId: draft.deviceId,
              entityType: 'sale_return',
              entityId: returnId,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return CreatedSaleReturn(
        returnId: returnId,
        operationId: operationId,
        refundAmount: total,
      );
    });
  }
}
