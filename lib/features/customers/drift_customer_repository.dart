import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../database/app_database.dart';
import 'customer_models.dart';

final class DriftCustomerRepository {
  DriftCustomerRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  Future<List<CustomerAccount>> search(
    String query, {
    bool activeOnly = false,
  }) async {
    final normalized = query.trim().toLowerCase();
    final pattern = '%$normalized%';
    final customers = await db
        .customSelect(
          '''select c.id,c.name,c.phone,c.address,c.notes,c.credit_limit,c.is_active,
      coalesce(sum(case when l.type in ('openingBalance','creditSale','adjustment') then l.amount else -l.amount end),0) balance,
      coalesce(sum(case when l.type='creditSale' then l.amount else 0 end),0) credit,
      coalesce(sum(case when l.type='paymentReceived' then l.amount else 0 end),0) payments
      from customers c left join customer_ledger_entries l on l.shop_id=c.shop_id and l.customer_id=c.id
      where c.shop_id=? and (?=0 or c.is_active=1) and (?='' or lower(c.name) like ? or lower(coalesce(c.phone,'')) like ?)
      group by c.id order by c.name limit 500''',
          variables: [
            Variable(shopId),
            Variable(activeOnly ? 1 : 0),
            Variable(normalized),
            Variable(pattern),
            Variable(pattern),
          ],
        )
        .get();
    return customers.map((result) {
      final row = result.data;
      return CustomerAccount(
        id: row['id'] as String,
        name: row['name'] as String,
        phone: row['phone'] as String?,
        address: row['address'] as String?,
        notes: row['notes'] as String?,
        creditLimitMinor: row['credit_limit'] as int?,
        isActive: (row['is_active'] as int) != 0,
        balanceMinor: row['balance'] as int,
        totalCreditMinor: row['credit'] as int,
        totalPaymentsMinor: row['payments'] as int,
      );
    }).toList();
  }

  Future<List<CustomerLedgerLine>> statement(String customerId) async {
    final rows =
        await (db.select(db.customerLedgerEntries)
              ..where(
                (t) =>
                    t.shopId.equals(shopId) & t.customerId.equals(customerId),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    var running = 0;
    final result = <CustomerLedgerLine>[];
    for (final row in rows) {
      running += row.amount.abs() * row.type.balanceSign;
      result.add(
        CustomerLedgerLine(
          id: row.id,
          type: row.type,
          amountMinor: row.amount,
          createdAt: row.createdAt,
          runningBalanceMinor: running,
          saleId: row.saleId,
          paymentReference: row.paymentReference,
          paymentMethod: row.paymentMethod,
          note: row.note,
        ),
      );
    }
    return result.reversed.toList();
  }
}
