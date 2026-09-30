import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../database/app_database.dart';
import '../../subscription/entitlement_policy.dart';

final class LocalCustomerPaymentService {
  LocalCustomerPaymentService(
    this.db,
    this.ids, {
    DateTime Function()? clock,
    this._authorizer = const AllowFinancialMutations(),
  }) : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final IdGenerator ids;
  final DateTime Function() _clock;
  final FinancialMutationAuthorizer _authorizer;

  Future<String> receive({
    required String shopId,
    required String customerId,
    required String actorId,
    required String deviceId,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {
    await _authorizer.authorize(shopId: shopId, deviceId: deviceId);
    return db.transaction(() async {
      if (amountMinor <= 0) {
        throw ArgumentError('Payment amount must be greater than zero.');
      }
      if (method != PaymentMethod.cash && method != PaymentMethod.digital) {
        throw ArgumentError('Customer payments must be cash or digital.');
      }
      final customer =
          await (db.select(db.customers)..where(
                (t) =>
                    t.id.equals(customerId) &
                    t.shopId.equals(shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (customer == null) {
        throw StateError('Customer is not active for this shop.');
      }
      final balanceRow = await db
          .customSelect(
            "select coalesce(sum(case when type in ('openingBalance','creditSale','adjustment') then amount else -amount end),0) balance from customer_ledger_entries where shop_id=? and customer_id=?",
            variables: [Variable(shopId), Variable(customerId)],
          )
          .getSingle();
      if (amountMinor > (balanceRow.data['balance'] as int)) {
        throw ArgumentError('Payment cannot exceed the customer balance.');
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
        throw StateError('Device is not active for this shop.');
      }
      final cashier =
          await (db.select(db.cashiers)..where(
                (t) =>
                    t.id.equals(actorId) &
                    t.shopId.equals(shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      final owner =
          await (db.select(db.shopUsers)..where(
                (t) =>
                    t.userId.equals(actorId) &
                    t.shopId.equals(shopId) &
                    t.isActive.equals(true) &
                    t.role.equals(ShopRole.owner.name),
              ))
              .getSingleOrNull();
      if (cashier == null && owner == null) {
        throw StateError('Actor is not active for this shop.');
      }
      final now = _clock().toUtc(),
          entryId = ids.next(),
          auditId = ids.next(),
          operationId = ids.next();
      await db
          .into(db.customerLedgerEntries)
          .insert(
            CustomerLedgerEntriesCompanion.insert(
              id: entryId,
              shopId: shopId,
              customerId: customerId,
              type: CustomerLedgerType.paymentReceived,
              amount: amountMinor,
              paymentReference: Value(reference),
              paymentMethod: Value(method.name),
              note: Value(note),
              createdBy: actorId,
              createdAt: now,
            ),
          );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: auditId,
              shopId: shopId,
              userId: actorId,
              action: 'customer.payment_received',
              entityType: 'customer_ledger_entry',
              entityId: entryId,
              newValue: Value(
                jsonEncode({'amount': amountMinor, 'method': method.name}),
              ),
              deviceId: Value(deviceId),
              createdAt: now,
            ),
          );
      final payload = {
        'version': 1,
        'operation': 'sync_customer_payment',
        'entry': {
          'id': entryId,
          'shop_id': shopId,
          'customer_id': customerId,
          'type': 'paymentReceived',
          'amount': amountMinor,
          'payment_reference': reference,
          'payment_method': method.name,
          'note': note,
          'created_by': actorId,
          'created_at': now.toIso8601String(),
        },
        'audit': {
          'id': auditId,
          'shop_id': shopId,
          'user_id': actorId,
          'action': 'customer.payment_received',
          'entity_type': 'customer_ledger_entry',
          'entity_id': entryId,
          'new_value': {'amount': amountMinor, 'method': method.name},
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
              entityType: 'customer_payment',
              entityId: entryId,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return operationId;
    });
  }
}
