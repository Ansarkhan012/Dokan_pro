import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../../database/app_database.dart';
import 'purchase_models.dart';

final class DriftPurchaseRepository {
  DriftPurchaseRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;
  Future<List<SupplierAccount>> suppliers(
    String query, {
    bool activeOnly = false,
  }) async {
    final q = query.trim().toLowerCase();
    final pattern = '%$q%';
    final suppliers = await db
        .customSelect(
          '''select s.id,s.name,s.contact_person,s.phone,s.address,s.notes,s.is_active,
      coalesce(sum(case when l.type in ('openingBalance','purchase','adjustment') then l.amount else -l.amount end),0) balance,
      coalesce(sum(case when l.type='purchase' then l.amount else 0 end),0) purchases,
      coalesce(sum(case when l.type='paymentMade' then l.amount else 0 end),0) payments
      from suppliers s left join supplier_ledger_entries l on l.shop_id=s.shop_id and l.supplier_id=s.id
      where s.shop_id=? and (?=0 or s.is_active=1) and (?='' or lower(s.name) like ? or lower(coalesce(s.phone,'')) like ?)
      group by s.id order by s.name limit 500''',
          variables: [
            Variable(shopId),
            Variable(activeOnly ? 1 : 0),
            Variable(q),
            Variable(pattern),
            Variable(pattern),
          ],
        )
        .get();
    return suppliers.map((result) {
      final s = result.data;
      return SupplierAccount(
        id: s['id'] as String,
        name: s['name'] as String,
        contactPerson: s['contact_person'] as String?,
        phone: s['phone'] as String?,
        address: s['address'] as String?,
        notes: s['notes'] as String?,
        isActive: (s['is_active'] as int) != 0,
        payableMinor: s['balance'] as int,
        totalPurchasesMinor: s['purchases'] as int,
        totalPaymentsMinor: s['payments'] as int,
      );
    }).toList();
  }

  Future<List<PurchaseSummary>> purchases({
    String? supplierId,
    String query = '',
    int limit = 100,
    int offset = 0,
  }) async {
    final q = query.trim().toLowerCase();
    final rows = await db
        .customSelect(
          '''select p.id,p.supplier_id,coalesce(s.name,'Unknown supplier') supplier_name,p.created_at,
      count(pi.id) item_count,p.total,p.paid_amount,p.payment_status,p.invoice_number,p.notes
      from purchases p left join suppliers s on s.id=p.supplier_id and s.shop_id=p.shop_id
      left join purchase_items pi on pi.purchase_id=p.id and pi.shop_id=p.shop_id
      where p.shop_id=? and (? is null or p.supplier_id=?) and (?='' or lower(coalesce(p.invoice_number,'')) like ? or lower(coalesce(s.name,'')) like ?)
      group by p.id order by p.created_at desc limit ? offset ?''',
          variables: [
            Variable(shopId),
            Variable(supplierId),
            Variable(supplierId),
            Variable(q),
            Variable('%$q%'),
            Variable('%$q%'),
            Variable(limit),
            Variable(offset),
          ],
        )
        .get();
    return rows.map((result) {
      final p = result.data;
      return PurchaseSummary(
        id: p['id'] as String,
        supplierId: p['supplier_id'] as String,
        supplierName: p['supplier_name'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(
          (p['created_at'] as int) * 1000,
          isUtc: true,
        ),
        itemCount: p['item_count'] as int,
        totalMinor: p['total'] as int,
        paidMinor: p['paid_amount'] as int,
        status: PaymentStatus.values.byName(p['payment_status'] as String),
        invoiceNumber: p['invoice_number'] as String?,
        notes: p['notes'] as String?,
      );
    }).toList();
  }

  Future<List<PurchaseLineView>> purchaseLines(String id) async =>
      (await (db.select(db.purchaseItems)..where(
                (t) => t.shopId.equals(shopId) & t.purchaseId.equals(id),
              ))
              .get())
          .map(
            (r) => PurchaseLineView(
              name: r.productNameSnapshot,
              quantity: r.quantity,
              unitCostMinor: r.unitCost,
              lineTotalMinor: r.lineTotal,
            ),
          )
          .toList();
  Future<List<SupplierLedgerLine>> statement(String supplierId) async {
    final rows =
        await (db.select(db.supplierLedgerEntries)
              ..where(
                (t) =>
                    t.shopId.equals(shopId) & t.supplierId.equals(supplierId),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    var running = 0;
    final out = <SupplierLedgerLine>[];
    for (final r in rows) {
      running += r.amount.abs() * r.type.balanceSign;
      out.add(
        SupplierLedgerLine(
          id: r.id,
          type: r.type,
          amountMinor: r.amount,
          date: r.createdAt,
          runningBalanceMinor: running,
          purchaseId: r.purchaseId,
          reference: r.paymentReference,
          note: r.note,
        ),
      );
    }
    return out.reversed.toList();
  }
}
