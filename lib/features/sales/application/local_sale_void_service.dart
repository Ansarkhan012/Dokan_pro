import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/domain/enums.dart';
import '../../../core/ids/id_generator.dart';
import '../../../database/app_database.dart';
import '../../../subscription/entitlement_policy.dart';

final class LocalSaleVoidService {
  LocalSaleVoidService(
    this.db,
    this.ids, {
    DateTime Function()? clock,
    this._authorizer = const AllowFinancialMutations(),
  }) : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final IdGenerator ids;
  final DateTime Function() _clock;
  final FinancialMutationAuthorizer _authorizer;

  Future<String> voidSale({
    required String shopId,
    required String saleId,
    required String ownerId,
    required String deviceId,
    required String reason,
  }) async {
    await _authorizer.authorize(shopId: shopId, deviceId: deviceId);
    return db.transaction(() async {
      if (reason.trim().isEmpty) {
        throw ArgumentError('Void reason is required.');
      }
      final owner =
          await (db.select(db.shopUsers)..where(
                (t) =>
                    t.shopId.equals(shopId) &
                    t.userId.equals(ownerId) &
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
                    t.id.equals(deviceId) &
                    t.shopId.equals(shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (device == null) {
        throw StateError('Active device required.');
      }
      final sale =
          await (db.select(db.sales)
                ..where((t) => t.id.equals(saleId) & t.shopId.equals(shopId)))
              .getSingleOrNull();
      if (sale == null) {
        throw StateError('Sale not found.');
      }
      final now = _clock().toUtc();
      if (now.difference(sale.createdAt.toUtc()) >
          const Duration(minutes: 15)) {
        throw StateError(
          'The 15-minute void window has expired. Use a return instead.',
        );
      }
      if (await (db.select(db.saleVoids)..where(
                (t) =>
                    t.shopId.equals(shopId) & t.originalSaleId.equals(saleId),
              ))
              .getSingleOrNull() !=
          null) {
        throw StateError('Sale is already voided.');
      }
      if (await (db.select(db.saleReturns)..where(
                (t) =>
                    t.shopId.equals(shopId) & t.originalSaleId.equals(saleId),
              ))
              .getSingleOrNull() !=
          null) {
        throw StateError('A sale with returns cannot be voided.');
      }
      final items = await (db.select(
        db.saleItems,
      )..where((t) => t.shopId.equals(shopId) & t.saleId.equals(saleId))).get();
      final payments = await (db.select(
        db.salePayments,
      )..where((t) => t.shopId.equals(shopId) & t.saleId.equals(saleId))).get();
      final breakdown = {
        for (final p in payments) p.paymentMethod.name: p.amount,
      };
      final voidId = ids.next(), auditId = ids.next(), operationId = ids.next();
      await db
          .into(db.saleVoids)
          .insert(
            SaleVoidsCompanion.insert(
              id: voidId,
              shopId: shopId,
              originalSaleId: saleId,
              deviceId: deviceId,
              amount: sale.grandTotal,
              reason: reason.trim(),
              paymentBreakdown: jsonEncode(breakdown),
              createdBy: ownerId,
              createdAt: now,
            ),
          );
      for (final item in items) {
        await db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: ids.next(),
                shopId: shopId,
                productId: item.productId,
                type: InventoryMovementType.returnIn,
                quantity: item.quantity,
                referenceType: const Value('sale_void'),
                referenceId: Value(voidId),
                note: Value(reason.trim()),
                createdBy: ownerId,
                deviceId: Value(deviceId),
                createdAt: now,
              ),
            );
      }
      final credit = payments
          .where((p) => p.paymentMethod == PaymentMethod.credit)
          .fold<int>(0, (sum, p) => sum + p.amount);
      if (credit > 0) {
        if (sale.customerId == null) {
          throw StateError('Credit sale has no customer.');
        }
        await db
            .into(db.customerLedgerEntries)
            .insert(
              CustomerLedgerEntriesCompanion.insert(
                id: ids.next(),
                shopId: shopId,
                customerId: sale.customerId!,
                type: CustomerLedgerType.refund,
                amount: credit,
                saleId: Value(saleId),
                note: Value(reason.trim()),
                createdBy: ownerId,
                createdAt: now,
              ),
            );
      }
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: auditId,
              shopId: shopId,
              userId: ownerId,
              action: 'sale.voided',
              entityType: 'sale_void',
              entityId: voidId,
              newValue: Value(
                jsonEncode({'sale_id': saleId, 'amount': sale.grandTotal}),
              ),
              deviceId: Value(deviceId),
              createdAt: now,
            ),
          );
      final payload = {
        'version': 1,
        'operation': 'sync_sale_void',
        'void': {
          'id': voidId,
          'shop_id': shopId,
          'original_sale_id': saleId,
          'device_id': deviceId,
          'amount': sale.grandTotal,
          'reason': reason.trim(),
          'payment_breakdown': breakdown,
          'created_by': ownerId,
          'created_at': now.toIso8601String(),
        },
        'audit_id': auditId,
      };
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operationId,
              shopId: shopId,
              deviceId: deviceId,
              entityType: 'sale_void',
              entityId: voidId,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return voidId;
    });
  }
}
