import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../database/app_database.dart';
import '../../subscription/entitlement_policy.dart';

final class LocalInventoryAdjustmentService {
  LocalInventoryAdjustmentService(
    this.db,
    this.ids, {
    DateTime Function()? clock,
    this._authorizer = const AllowFinancialMutations(),
  }) : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final IdGenerator ids;
  final DateTime Function() _clock;
  final FinancialMutationAuthorizer _authorizer;

  Future<String> record({
    required String shopId,
    required String productId,
    required String ownerId,
    required String deviceId,
    required InventoryMovementType type,
    required int quantity,
    required String note,
  }) async {
    await _authorizer.authorize(shopId: shopId, deviceId: deviceId);
    return db.transaction(() async {
      if (type != InventoryMovementType.openingStock &&
          type != InventoryMovementType.manualAdjustment &&
          type != InventoryMovementType.damage) {
        throw ArgumentError('Unsupported inventory adjustment type.');
      }
      if (quantity == 0) throw ArgumentError('Quantity cannot be zero.');
      if (type != InventoryMovementType.manualAdjustment && quantity < 0) {
        throw ArgumentError('Quantity must be positive for this adjustment.');
      }
      if (note.trim().isEmpty) throw ArgumentError('A reason is required.');
      final product =
          await (db.select(
                db.shopProducts,
              )..where((t) => t.id.equals(productId) & t.shopId.equals(shopId)))
              .getSingleOrNull();
      if (product == null) throw StateError('Product is outside this shop.');
      final owner =
          await (db.select(db.shopUsers)..where(
                (t) =>
                    t.shopId.equals(shopId) &
                    t.userId.equals(ownerId) &
                    t.role.equals(ShopRole.owner.name) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (owner == null) throw StateError('Active owner required.');
      final device =
          await (db.select(db.devices)..where(
                (t) =>
                    t.id.equals(deviceId) &
                    t.shopId.equals(shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (device == null) throw StateError('Active device required.');

      final signed = switch (type) {
        InventoryMovementType.damage => -quantity.abs(),
        InventoryMovementType.openingStock => quantity.abs(),
        InventoryMovementType.manualAdjustment => quantity,
        _ => throw StateError('unreachable'),
      };
      final current = await db
          .customSelect(
            'select coalesce(sum(quantity),0) stock from inventory_movements where shop_id=? and product_id=?',
            variables: [Variable(shopId), Variable(productId)],
          )
          .getSingle();
      final shop = await (db.select(
        db.shops,
      )..where((t) => t.id.equals(shopId))).getSingle();
      if (!shop.allowNegativeStock &&
          (current.read<int>('stock') + signed) < 0) {
        throw StateError('This adjustment would make stock negative.');
      }
      final now = _clock().toUtc();
      final movementId = ids.next(),
          auditId = ids.next(),
          operationId = ids.next();
      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              id: movementId,
              shopId: shopId,
              productId: productId,
              type: type,
              quantity: signed,
              referenceType: const Value('manual_inventory'),
              referenceId: Value(operationId),
              note: Value(note.trim()),
              createdBy: ownerId,
              deviceId: Value(deviceId),
              createdAt: now,
            ),
          );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: auditId,
              shopId: shopId,
              userId: ownerId,
              action: 'inventory.adjusted',
              entityType: 'inventory_movement',
              entityId: movementId,
              newValue: Value(
                jsonEncode({
                  'product_id': productId,
                  'type': type.name,
                  'quantity': signed,
                }),
              ),
              deviceId: Value(deviceId),
              createdAt: now,
            ),
          );
      final payload = {
        'version': 1,
        'operation': 'sync_inventory_adjustment',
        'movement': {
          'id': movementId,
          'shop_id': shopId,
          'product_id': productId,
          'type': type.name,
          'quantity': signed,
          'reference_type': 'manual_inventory',
          'reference_id': operationId,
          'note': note.trim(),
          'created_by': ownerId,
          'device_id': deviceId,
          'created_at': now.toIso8601String(),
        },
        'audit': {
          'id': auditId,
          'shop_id': shopId,
          'user_id': ownerId,
          'action': 'inventory.adjusted',
          'entity_type': 'inventory_movement',
          'entity_id': movementId,
          'new_value': {
            'product_id': productId,
            'type': type.name,
            'quantity': signed,
          },
          'device_id': deviceId,
          'created_at': now.toIso8601String(),
        },
      };
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operationId,
              shopId: shopId,
              deviceId: deviceId,
              entityType: 'inventory_movement',
              entityId: movementId,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return movementId;
    });
  }
}
