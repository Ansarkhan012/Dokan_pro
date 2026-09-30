import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import 'report_models.dart';

final class DriftReportingRepository {
  DriftReportingRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;
  Future<OwnerReport> load(
    ReportRange range, {
    ReportRangePreset preset = ReportRangePreset.today,
  }) async {
    final vars = [
      Variable(shopId),
      Variable(range.startUtc),
      Variable(range.endUtc),
    ];
    Future<Map<String, Object?>> one(String sql) async =>
        (await db.customSelect(sql, variables: vars).getSingle()).data;
    final sales = await one(
      "select coalesce(sum(grand_total),0) gross,count(*) bills from sales where shop_id=? and created_at>=? and created_at<?",
    );
    final returned =
        (await db
                .customSelect(
                  "select coalesce((select sum(refund_amount) from sale_returns where shop_id=? and created_at>=? and created_at<?),0)+coalesce((select sum(amount) from sale_voids where shop_id=? and created_at>=? and created_at<?),0) amount",
                  variables: [...vars, ...vars],
                )
                .getSingle())
            .data;
    final partial = await db
        .customSelect(
          'select count(*) count from sales s where s.shop_id=? and s.created_at>=? and s.created_at<? and exists(select 1 from sale_returns r where r.shop_id=s.shop_id and r.original_sale_id=s.id) and not exists(select 1 from sale_voids v where v.shop_id=s.shop_id and v.original_sale_id=s.id) and (select coalesce(sum(refund_amount),0) from sale_returns r where r.shop_id=s.shop_id and r.original_sale_id=s.id)<s.grand_total',
          variables: vars,
        )
        .getSingle();
    final purchases = await one(
      'select coalesce(sum(total),0) total,coalesce(sum(paid_amount),0) paid,count(*) count from purchases where shop_id=? and created_at>=? and created_at<?',
    );
    final expenses = await one(
      'select coalesce(sum(amount),0) total from expenses where shop_id=? and coalesce(expense_at,created_at)>=? and coalesce(expense_at,created_at)<?',
    );
    final payments = await db.customSelect(
      '''select
      coalesce((select sum(amount) from sale_payments p join sales s on s.id=p.sale_id and s.shop_id=p.shop_id where s.shop_id=? and s.created_at>=? and s.created_at<? and p.payment_method='cash'),0)
        -coalesce((select sum(refund_amount) from sale_returns where shop_id=? and created_at>=? and created_at<? and refund_method='cash'),0)
        -coalesce((select sum(cast(json_extract(payment_breakdown,'\$.cash') as integer)) from sale_voids where shop_id=? and created_at>=? and created_at<?),0) cash,
      coalesce((select sum(amount) from sale_payments p join sales s on s.id=p.sale_id and s.shop_id=p.shop_id where s.shop_id=? and s.created_at>=? and s.created_at<? and p.payment_method='digital'),0)
        -coalesce((select sum(refund_amount) from sale_returns where shop_id=? and created_at>=? and created_at<? and refund_method='digital'),0)
        -coalesce((select sum(cast(json_extract(payment_breakdown,'\$.digital') as integer)) from sale_voids where shop_id=? and created_at>=? and created_at<?),0) digital,
      coalesce((select sum(amount) from sale_payments p join sales s on s.id=p.sale_id and s.shop_id=p.shop_id where s.shop_id=? and s.created_at>=? and s.created_at<? and p.payment_method='credit'),0)
        -coalesce((select sum(refund_amount) from sale_returns where shop_id=? and created_at>=? and created_at<? and refund_method='credit'),0)
        -coalesce((select sum(cast(json_extract(payment_breakdown,'\$.credit') as integer)) from sale_voids where shop_id=? and created_at>=? and created_at<?),0) credit''',
      variables: List.generate(9, (_) => vars).expand((x) => x).toList(),
    ).getSingle();
    final balances = await db
        .customSelect(
          "select coalesce((select sum(case when type in ('openingBalance','creditSale','adjustment') then amount else -amount end) from customer_ledger_entries where shop_id=?),0) receivables,coalesce((select sum(case when type in ('openingBalance','purchase','adjustment') then amount else -amount end) from supplier_ledger_entries where shop_id=?),0) payables",
          variables: [Variable(shopId), Variable(shopId)],
        )
        .getSingle();
    final low = await db
        .customSelect(
          'select sp.id,coalesce(sp.custom_name,mp.name,\'Unnamed\') name,coalesce(sum(im.quantity),0) stock,sp.low_stock_level threshold from shop_products sp left join master_products mp on mp.id=sp.master_product_id left join inventory_movements im on im.product_id=sp.id and im.shop_id=sp.shop_id where sp.shop_id=? and sp.is_active=1 and sp.stock_tracking_enabled=1 and sp.low_stock_level is not null group by sp.id having stock<=threshold order by stock-threshold',
          variables: [Variable(shopId)],
        )
        .get();
    final insights = await _productInsights(vars);
    final summary = ReportSummary(
      grossSales: sales['gross'] as int,
      returns: returned['amount'] as int,
      sales: (sales['gross'] as int) - (returned['amount'] as int),
      purchases: purchases['total'] as int,
      cogs: insights.$4,
      expenses: expenses['total'] as int,
      receivables: balances.data['receivables'] as int,
      payables: balances.data['payables'] as int,
      billCount: sales['bills'] as int,
      purchaseCount: purchases['count'] as int,
      cash: payments.data['cash'] as int,
      digital: payments.data['digital'] as int,
      credit: payments.data['credit'] as int,
      purchasePaid: purchases['paid'] as int,
      purchaseCredit: (purchases['total'] as int) - (purchases['paid'] as int),
      lowStockCount: low.length,
      missingCostLines: insights.$5,
      partialReturnCount: partial.data['count'] as int,
    );
    return OwnerReport(
      summary: summary,
      trend: await _trend(range, preset),
      topSalesProducts: insights.$1,
      topQuantityProducts: insights.$2,
      topProfitProducts: insights.$3,
      expensesByCategory: await _rank(
        'select category label,sum(amount) value,0 secondary from expenses where shop_id=? and coalesce(expense_at,created_at)>=? and coalesce(expense_at,created_at)<? group by category order by value desc',
        vars,
      ),
      expensesByMethod: await _rank(
        'select payment_method label,sum(amount) value,0 secondary from expenses where shop_id=? and coalesce(expense_at,created_at)>=? and coalesce(expense_at,created_at)<? group by payment_method order by value desc',
        vars,
      ),
      topDebtors: await _currentRank(
        'customers',
        'customer_ledger_entries',
        true,
      ),
      topSuppliers: await _currentRank(
        'suppliers',
        'supplier_ledger_entries',
        false,
      ),
      lowStock: [
        for (final r in low)
          RankedValue(
            r.data['name'] as String,
            r.data['stock'] as int,
            secondary: r.data['threshold'] as int,
          ),
      ],
      cashiers: await _cashiers(vars),
    );
  }

  Future<List<RankedValue>> _rank(String sql, List<Variable> vars) async =>
      (await db.customSelect(sql, variables: vars).get())
          .map(
            (r) => RankedValue(
              r.data['label'] as String,
              r.data['value'] as int,
              secondary: (r.data['secondary'] as int?) ?? 0,
            ),
          )
          .toList();

  Future<(List<RankedValue>, List<RankedValue>, List<RankedValue>, int, int)>
  _productInsights(List<Variable> vars) async {
    final rows = await db
        .customSelect(
          '''with movements as (
      select si.product_id,si.product_name_snapshot label,si.line_total sales,
      si.quantity quantity,(si.cost_price_snapshot*si.quantity+500)/1000 cogs,
      case when si.cost_price_snapshot<0 then 1 else 0 end missing
      from sale_items si join sales s on s.id=si.sale_id and s.shop_id=si.shop_id
      where s.shop_id=? and s.created_at>=? and s.created_at<? and s.sale_status='completed'
      union all
      select ri.product_id,ri.product_name_snapshot,-ri.refund_amount,-ri.quantity,
      -(si.cost_price_snapshot*ri.quantity+500)/1000,0
      from sale_return_items ri join sale_returns r on r.id=ri.return_id and r.shop_id=ri.shop_id
      join sale_items si on si.id=ri.original_sale_item_id and si.shop_id=ri.shop_id
      where r.shop_id=? and r.created_at>=? and r.created_at<?
      union all
      select si.product_id,si.product_name_snapshot,-si.line_total,-si.quantity,
      -(si.cost_price_snapshot*si.quantity+500)/1000,0
      from sale_items si join sale_voids v on v.original_sale_id=si.sale_id and v.shop_id=si.shop_id
      where v.shop_id=? and v.created_at>=? and v.created_at<?),
      product as materialized (
      select product_id,label,sum(sales) sales,sum(quantity) quantity,
      sum(sales-cogs) profit,sum(cogs) cogs,sum(missing) missing
      from movements group by product_id,label)
      select 'sales' kind,label,sales value,quantity secondary from (select * from product order by sales desc limit 10)
      union all select 'quantity',label,quantity,sales from (select * from product order by quantity desc limit 10)
      union all select 'profit',label,profit,0 from (select * from product order by profit desc limit 10)
      union all select 'totals','',coalesce(sum(cogs),0),coalesce(sum(missing),0) from product''',
          variables: [...vars, ...vars, ...vars],
        )
        .get();
    List<RankedValue> values(String kind) => rows
        .where((row) => row.data['kind'] == kind)
        .map(
          (row) => RankedValue(
            row.data['label'] as String,
            row.data['value'] as int,
            secondary: row.data['secondary'] as int,
          ),
        )
        .toList();
    final totals = rows.singleWhere((row) => row.data['kind'] == 'totals');
    return (
      values('sales'),
      values('quantity'),
      values('profit'),
      totals.data['value'] as int,
      totals.data['secondary'] as int,
    );
  }

  Future<List<RankedValue>> _currentRank(
    String party,
    String ledger,
    bool customer,
  ) async {
    final fk = customer ? 'customer_id' : 'supplier_id';
    final plus = customer
        ? "'openingBalance','creditSale','adjustment'"
        : "'openingBalance','purchase','adjustment'";
    final rows = await db
        .customSelect(
          'select p.name label,sum(case when l.type in ($plus) then l.amount else -l.amount end) value from $party p join $ledger l on l.$fk=p.id and l.shop_id=p.shop_id where p.shop_id=? group by p.id having value>0 order by value desc limit 10',
          variables: [Variable(shopId)],
        )
        .get();
    return rows
        .map(
          (r) => RankedValue(r.data['label'] as String, r.data['value'] as int),
        )
        .toList();
  }

  Future<List<ReportBucket>> _trend(ReportRange r, ReportRangePreset p) async {
    final fmt = p == ReportRangePreset.year ? '%Y-%m' : '%Y-%m-%d';
    final rows = await db
        .customSelect(
          "select bucket,sum(sales) sales,sum(purchases) purchases from (select strftime('$fmt',created_at,'unixepoch','+5 hours') bucket,grand_total sales,0 purchases from sales where shop_id=? and created_at>=? and created_at<? and sale_status='completed' union all select strftime('$fmt',created_at,'unixepoch','+5 hours'),-refund_amount,0 from sale_returns where shop_id=? and created_at>=? and created_at<? union all select strftime('$fmt',created_at,'unixepoch','+5 hours'),-amount,0 from sale_voids where shop_id=? and created_at>=? and created_at<? union all select strftime('$fmt',created_at,'unixepoch','+5 hours'),0,total from purchases where shop_id=? and created_at>=? and created_at<?) group by bucket order by bucket",
          variables: [
            Variable(shopId),
            Variable(r.startUtc),
            Variable(r.endUtc),
            Variable(shopId),
            Variable(r.startUtc),
            Variable(r.endUtc),
            Variable(shopId),
            Variable(r.startUtc),
            Variable(r.endUtc),
            Variable(shopId),
            Variable(r.startUtc),
            Variable(r.endUtc),
          ],
        )
        .get();
    return rows
        .map(
          (x) => ReportBucket(
            x.data['bucket'] as String,
            x.data['sales'] as int,
            x.data['purchases'] as int,
          ),
        )
        .toList();
  }

  Future<List<CashierReport>> _cashiers(List<Variable> v) async {
    final rows = await db
        .customSelect(
          "select coalesce(c.display_name,s.cashier_id) name,sum(s.grand_total) sales,count(distinct s.id) bills,coalesce(sum(case when sp.payment_method='cash' then sp.amount else 0 end),0) cash,coalesce(sum(case when sp.payment_method='digital' then sp.amount else 0 end),0) digital,coalesce(sum(case when sp.payment_method='credit' then sp.amount else 0 end),0) credit from sales s left join cashiers c on c.id=s.cashier_id and c.shop_id=s.shop_id left join sale_payments sp on sp.sale_id=s.id and sp.shop_id=s.shop_id where s.shop_id=? and s.created_at>=? and s.created_at<? and s.sale_status='completed' group by s.cashier_id order by sales desc",
          variables: v,
        )
        .get();
    return rows
        .map(
          (r) => CashierReport(
            r.data['name'] as String,
            r.data['sales'] as int,
            r.data['bills'] as int,
            r.data['cash'] as int,
            r.data['digital'] as int,
            r.data['credit'] as int,
          ),
        )
        .toList();
  }
}
