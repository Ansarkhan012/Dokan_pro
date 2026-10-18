import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../database/app_database.dart';
import '../../subscription/entitlement_policy.dart';
import '../../sync/sync_time.dart';
import 'purchase_models.dart';

final class LocalPurchaseService {
  LocalPurchaseService(
    this.db,
    this.ids, {
    DateTime Function()? clock,
    this._authorizer = const AllowFinancialMutations(),
  }) : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final IdGenerator ids;
  final DateTime Function() _clock;
  final FinancialMutationAuthorizer _authorizer;
  Future<CreatedPurchase> create(PurchaseDraft draft) async {
    await _authorizer.authorize(shopId: draft.shopId, deviceId: draft.deviceId);
    return db.transaction(() async {
      final now = (draft.purchaseDate ?? _clock()).toUtc();
      if (draft.lines.isEmpty) {
        throw ArgumentError('Purchase needs at least one item.');
      }
      if (draft.lines.map((e) => e.productId).toSet().length !=
          draft.lines.length) {
        throw ArgumentError('A product can appear only once.');
      }
      if (await (db.select(db.shopUsers)..where(
                (t) =>
                    t.shopId.equals(draft.shopId) &
                    t.userId.equals(draft.ownerId) &
                    t.role.equals(ShopRole.owner.name) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active owner required.');
      }
      if (await (db.select(db.devices)..where(
                (t) =>
                    t.id.equals(draft.deviceId) &
                    t.shopId.equals(draft.shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active device required.');
      }
      if (await (db.select(db.suppliers)..where(
                (t) =>
                    t.id.equals(draft.supplierId) &
                    t.shopId.equals(draft.shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active supplier required.');
      }
      final itemData = <Map<String, Object?>>[];
      var total = 0;
      for (final line in draft.lines) {
        if (line.quantity <= 0 || line.unitCostMinor < 0) {
          throw ArgumentError('Quantity and cost are invalid.');
        }
        final product =
            await (db.select(db.shopProducts)..where(
                  (t) =>
                      t.id.equals(line.productId) &
                      t.shopId.equals(draft.shopId) &
                      t.isActive.equals(true),
                ))
                .getSingleOrNull();
        if (product == null) throw StateError('Active product required.');
        final name = await _name(product);
        final lineTotal = (line.unitCostMinor * line.quantity + 500) ~/ 1000;
        total += lineTotal;
        itemData.add({
          'id': ids.next(),
          'product': product.id,
          'name': name,
          'quantity': line.quantity,
          'cost': line.unitCostMinor,
          'total': lineTotal,
          'movement': ids.next(),
        });
      }
      var paid = 0;
      for (final p in draft.payments) {
        if ((p.method != PaymentMethod.cash &&
                p.method != PaymentMethod.digital) ||
            p.amountMinor <= 0) {
          throw ArgumentError(
            'Purchase payments must be positive cash or digital amounts.',
          );
        }
        paid += p.amountMinor;
      }
      if (paid > total) {
        throw ArgumentError('Paid amount cannot exceed purchase total.');
      }
      final due = total - paid;
      final purchaseId = ids.next();
      await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              shopId: draft.shopId,
              supplierId: Value(draft.supplierId),
              deviceId: Value(draft.deviceId),
              invoiceNumber: Value(draft.invoiceNumber),
              notes: Value(draft.notes),
              subtotal: total,
              discountTotal: 0,
              total: total,
              paidAmount: Value(paid),
              paymentStatus: paid == total
                  ? PaymentStatus.paid
                  : paid == 0
                  ? PaymentStatus.unpaid
                  : PaymentStatus.partiallyPaid,
              createdBy: draft.ownerId,
              createdAt: now,
            ),
          );
      for (final row in itemData) {
        await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                id: row['id']! as String,
                shopId: draft.shopId,
                purchaseId: purchaseId,
                productId: row['product']! as String,
                productNameSnapshot: Value(row['name']! as String),
                quantity: row['quantity']! as int,
                unitCost: row['cost']! as int,
                lineTotal: row['total']! as int,
                createdAt: now,
              ),
            );
        await db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: row['movement']! as String,
                shopId: draft.shopId,
                productId: row['product']! as String,
                type: InventoryMovementType.purchase,
                quantity: row['quantity']! as int,
                referenceType: const Value('purchase'),
                referenceId: Value(purchaseId),
                createdBy: draft.ownerId,
                deviceId: Value(draft.deviceId),
                createdAt: now,
              ),
            );
      }
      for (final p in draft.payments) {
        await db
            .into(db.purchasePayments)
            .insert(
              PurchasePaymentsCompanion.insert(
                id: ids.next(),
                shopId: draft.shopId,
                purchaseId: purchaseId,
                paymentMethod: p.method,
                amount: p.amountMinor,
                reference: Value(p.reference),
                createdAt: now,
              ),
            );
      }
      if (due > 0) {
        await db
            .into(db.supplierLedgerEntries)
            .insert(
              SupplierLedgerEntriesCompanion.insert(
                id: ids.next(),
                shopId: draft.shopId,
                supplierId: draft.supplierId,
                type: SupplierLedgerType.purchase,
                amount: due,
                purchaseId: Value(purchaseId),
                createdBy: draft.ownerId,
                createdAt: now,
              ),
            );
      }
      final auditId = ids.next();
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: auditId,
              shopId: draft.shopId,
              userId: draft.ownerId,
              action: 'purchase.completed',
              entityType: 'purchase',
              entityId: purchaseId,
              newValue: Value(
                jsonEncode({'total': total, 'paid': paid, 'due': due}),
              ),
              deviceId: Value(draft.deviceId),
              createdAt: now,
            ),
          );
      final payload = await _payload(draft.shopId, purchaseId, auditId);
      final operationId = ids.next();
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operationId,
              shopId: draft.shopId,
              deviceId: draft.deviceId,
              entityType: 'purchase_aggregate',
              entityId: purchaseId,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return CreatedPurchase(
        purchaseId: purchaseId,
        operationId: operationId,
        totalMinor: total,
        paidMinor: paid,
        dueMinor: due,
      );
    });
  }

  Future<String> _name(ShopProduct p) async {
    if (p.customName != null) return p.customName!;
    final m = await (db.select(
      db.masterProducts,
    )..where((t) => t.id.equals(p.masterProductId!))).getSingle();
    return m.name;
  }

  Future<Map<String, Object?>> _payload(
    String shop,
    String purchase,
    String audit,
  ) async {
    // Instants leave the device as UTC ('Z'), never as a local wall clock.
    const s = SyncTime.payloadSerializer;
    final p = await (db.select(
      db.purchases,
    )..where((t) => t.id.equals(purchase) & t.shopId.equals(shop))).getSingle();
    final i =
        await (db.select(db.purchaseItems)..where(
              (t) => t.purchaseId.equals(purchase) & t.shopId.equals(shop),
            ))
            .get();
    final pay =
        await (db.select(db.purchasePayments)..where(
              (t) => t.purchaseId.equals(purchase) & t.shopId.equals(shop),
            ))
            .get();
    final mov =
        await (db.select(db.inventoryMovements)..where(
              (t) => t.referenceId.equals(purchase) & t.shopId.equals(shop),
            ))
            .get();
    final led =
        await (db.select(db.supplierLedgerEntries)..where(
              (t) => t.purchaseId.equals(purchase) & t.shopId.equals(shop),
            ))
            .get();
    return {
      'version': 1,
      'operation': 'sync_purchase_transaction',
      'purchase': p.toJson(serializer: s),
      'purchase_items': i.map((e) => e.toJson(serializer: s)).toList(),
      'payments': pay.map((e) => e.toJson(serializer: s)).toList(),
      'inventory_movements': mov.map((e) => e.toJson(serializer: s)).toList(),
      'supplier_ledger_entries': led
          .map((e) => e.toJson(serializer: s))
          .toList(),
      'audit_id': audit,
    };
  }
}
