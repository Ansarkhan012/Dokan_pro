import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../database/app_database.dart';
import '../../subscription/entitlement_policy.dart';

final class LocalSupplierPaymentService {
  LocalSupplierPaymentService(
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
    required String supplierId,
    required String ownerId,
    required String deviceId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {
    await _authorizer.authorize(shopId: shopId, deviceId: deviceId);
    return db.transaction(() async {
      if (amountMinor <= 0) {
        throw ArgumentError('Amount must be greater than zero.');
      }
      if (method != PaymentMethod.cash && method != PaymentMethod.digital) {
        throw ArgumentError('Method must be cash or digital.');
      }
      if (await (db.select(db.shopUsers)..where(
                (t) =>
                    t.shopId.equals(shopId) &
                    t.userId.equals(ownerId) &
                    t.role.equals(ShopRole.owner.name) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active owner required.');
      }
      if (await (db.select(db.devices)..where(
                (t) =>
                    t.id.equals(deviceId) &
                    t.shopId.equals(shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active device required.');
      }
      if (await (db.select(db.suppliers)..where(
                (t) =>
                    t.id.equals(supplierId) &
                    t.shopId.equals(shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active supplier required.');
      }
      final balanceRow = await db
          .customSelect(
            "select coalesce(sum(case when type in ('openingBalance','purchase','adjustment') then amount else -amount end),0) balance from supplier_ledger_entries where shop_id=? and supplier_id=?",
            variables: [Variable(shopId), Variable(supplierId)],
          )
          .getSingle();
      if (amountMinor > (balanceRow.data['balance'] as int)) {
        throw ArgumentError('Payment cannot exceed the supplier payable.');
      }
      final now = _clock().toUtc(),
          entry = ids.next(),
          audit = ids.next(),
          operation = ids.next();
      await db
          .into(db.supplierLedgerEntries)
          .insert(
            SupplierLedgerEntriesCompanion.insert(
              id: entry,
              shopId: shopId,
              supplierId: supplierId,
              type: SupplierLedgerType.paymentMade,
              amount: amountMinor,
              paymentReference: Value(reference),
              paymentMethod: Value(method.name),
              note: Value(note),
              createdBy: ownerId,
              createdAt: now,
            ),
          );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: audit,
              shopId: shopId,
              userId: ownerId,
              action: 'supplier.payment_made',
              entityType: 'supplier_ledger_entry',
              entityId: entry,
              newValue: Value(
                jsonEncode({'amount': amountMinor, 'method': method.name}),
              ),
              deviceId: Value(deviceId),
              createdAt: now,
            ),
          );
      final payload = {
        'version': 1,
        'operation': 'sync_supplier_payment',
        'entry': {
          'id': entry,
          'shop_id': shopId,
          'supplier_id': supplierId,
          'type': 'paymentMade',
          'amount': amountMinor,
          'payment_reference': reference,
          'payment_method': method.name,
          'note': note,
          'created_by': ownerId,
          'created_at': now.toIso8601String(),
        },
        'audit': {
          'id': audit,
          'shop_id': shopId,
          'user_id': ownerId,
          'action': 'supplier.payment_made',
          'entity_type': 'supplier_ledger_entry',
          'entity_id': entry,
          'new_value': {'amount': amountMinor, 'method': method.name},
          'device_id': deviceId,
          'created_at': now.toIso8601String(),
        },
      };
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operation,
              shopId: shopId,
              deviceId: deviceId,
              entityType: 'supplier_payment',
              entityId: entry,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return operation;
    });
  }
}
