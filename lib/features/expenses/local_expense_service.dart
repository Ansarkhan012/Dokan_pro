import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../database/app_database.dart';
import '../../subscription/entitlement_policy.dart';
import 'expense_models.dart';

final class LocalExpenseService {
  LocalExpenseService(
    this.db,
    this.ids, {
    DateTime Function()? clock,
    this._authorizer = const AllowFinancialMutations(),
  }) : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final IdGenerator ids;
  final DateTime Function() _clock;
  final FinancialMutationAuthorizer _authorizer;
  Future<CreatedExpense> create(ExpenseDraft d) async {
    await _authorizer.authorize(shopId: d.shopId, deviceId: d.deviceId);
    return db.transaction(() async {
      if (d.amountMinor <= 0) {
        throw ArgumentError('Expense amount must be greater than zero.');
      }
      if (d.description.trim().isEmpty) {
        throw ArgumentError('Description is required.');
      }
      if (d.paymentMethod != PaymentMethod.cash &&
          d.paymentMethod != PaymentMethod.digital) {
        throw ArgumentError('Expense payment must be cash or digital.');
      }
      if (await (db.select(db.shopUsers)..where(
                (t) =>
                    t.shopId.equals(d.shopId) &
                    t.userId.equals(d.ownerId) &
                    t.role.equals(ShopRole.owner.name) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active owner required.');
      }
      if (await (db.select(db.devices)..where(
                (t) =>
                    t.id.equals(d.deviceId) &
                    t.shopId.equals(d.shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull() ==
          null) {
        throw StateError('Active device required.');
      }
      final category =
          await (db.select(db.expenseCategories)..where(
                (t) =>
                    t.id.equals(d.categoryId) &
                    t.shopId.equals(d.shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (category == null) {
        throw StateError('Active expense category required.');
      }
      final now = _clock().toUtc(),
          expenseId = ids.next(),
          auditId = ids.next(),
          operationId = ids.next();
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: expenseId,
              shopId: d.shopId,
              category: category.name,
              categoryId: Value(category.id),
              amount: d.amountMinor,
              paymentMethod: Value(d.paymentMethod),
              description: Value(d.description.trim()),
              note: Value(d.note),
              reference: Value(d.reference),
              deviceId: Value(d.deviceId),
              expenseAt: Value(d.expenseAt.toUtc()),
              createdBy: d.ownerId,
              createdAt: now,
            ),
          );
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: auditId,
              shopId: d.shopId,
              userId: d.ownerId,
              action: 'expense.created',
              entityType: 'expense',
              entityId: expenseId,
              newValue: Value(
                jsonEncode({
                  'amount': d.amountMinor,
                  'category': category.name,
                }),
              ),
              deviceId: Value(d.deviceId),
              createdAt: now,
            ),
          );
      final payload = {
        'version': 1,
        'operation': 'sync_expense',
        'expense': {
          'id': expenseId,
          'shop_id': d.shopId,
          'category_id': category.id,
          'category': category.name,
          'amount': d.amountMinor,
          'payment_method': d.paymentMethod.name,
          'expense_at': d.expenseAt.toUtc().toIso8601String(),
          'description': d.description.trim(),
          'note': d.note,
          'reference': d.reference,
          'created_by': d.ownerId,
          'device_id': d.deviceId,
          'created_at': now.toIso8601String(),
        },
        'audit': {
          'id': auditId,
          'shop_id': d.shopId,
          'user_id': d.ownerId,
          'action': 'expense.created',
          'entity_type': 'expense',
          'entity_id': expenseId,
          'new_value': {'amount': d.amountMinor, 'category': category.name},
          'device_id': d.deviceId,
          'created_at': now.toIso8601String(),
        },
      };
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operationId,
              shopId: d.shopId,
              deviceId: d.deviceId,
              entityType: 'expense',
              entityId: expenseId,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return CreatedExpense(expenseId, operationId);
    });
  }
}
